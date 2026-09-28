//! Secret agent của NetworkManager.
//!
//! Khi NetworkManager cần mật khẩu (kết nối mạng Wi-Fi mới, mật khẩu đã lưu
//! bị sai, mạng doanh nghiệp), nó hỏi các agent đã đăng ký. glassd đăng ký
//! một agent trên system bus và chuyển câu hỏi sang shell (xem prompts.rs).
//! glassd không tự lưu mật khẩu: NetworkManager lưu theo cờ của kết nối.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use futures_util::StreamExt;
use tokio::sync::Mutex;
use tracing::{debug, info, warn};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use zbus::{Connection, fdo, interface};

use crate::prompts::{Answer, Prompt, PromptError, Prompts};

pub const AGENT_PATH: &str = "/org/freedesktop/NetworkManager/SecretAgent";
const NM_NAME: &str = "org.freedesktop.NetworkManager";
/// Tên agent báo cho NetworkManager.
const IDENTIFIER: &str = "io.github.canxphung.glass";
/// NetworkManager chờ agent khoảng 120 giây; trả lời trước lúc đó.
const TIMEOUT: Duration = Duration::from_secs(110);

// Cờ của GetSecrets (NMSecretAgentGetSecretsFlags).
const ALLOW_INTERACTION: u32 = 0x1;
const REQUEST_NEW: u32 = 0x2;

/// a{sa{sv}}: setting → khoá → giá trị.
pub type Settings = HashMap<String, HashMap<String, OwnedValue>>;

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.freedesktop.NetworkManager.SecretAgent")]
pub enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    NoSecrets(String),
    UserCanceled(String),
}

impl From<PromptError> for AgentError {
    fn from(e: PromptError) -> Self {
        match e {
            PromptError::Canceled => Self::UserCanceled(e.to_string()),
            PromptError::NoUi | PromptError::Timeout => Self::NoSecrets(e.to_string()),
        }
    }
}

/// Một yêu cầu mật khẩu glassd hiểu được.
#[derive(Debug, PartialEq)]
struct SecretRequest {
    ssid: String,
    security: &'static str,
    fields: &'static [&'static str],
}

impl SecretRequest {
    fn parse(connection: &Settings, setting_name: &str) -> Option<Self> {
        let ssid = bytes(connection, "802-11-wireless", "ssid")
            .map(|b| String::from_utf8_lossy(&b).into_owned())
            .or_else(|| string(connection, "connection", "id"))?;
        let (security, fields): (&'static str, &'static [&'static str]) = match setting_name {
            "802-11-wireless-security" => {
                match string(connection, "802-11-wireless-security", "key-mgmt").as_deref() {
                    Some("none") => ("wep", &["wep-key0"]),
                    Some("wpa-psk" | "sae") | None => ("psk", &["psk"]),
                    // Mạng doanh nghiệp: NetworkManager hỏi setting 802-1x.
                    _ => return None,
                }
            }
            "802-1x" => ("enterprise", &["identity", "password"]),
            _ => return None,
        };
        Some(Self { ssid, security, fields })
    }

    fn secrets(&self, setting_name: &str, answer: &Answer) -> Result<Settings, AgentError> {
        let mut values = HashMap::new();
        for &field in self.fields {
            let value = answer
                .get(field)
                .filter(|v| !v.is_empty())
                .ok_or_else(|| AgentError::NoSecrets(format!("thiếu {field}")))?;
            values.insert(field.to_string(), owned(Value::from(value.as_str())));
        }
        Ok(HashMap::from([(setting_name.to_string(), values)]))
    }
}

fn owned(value: Value<'_>) -> OwnedValue {
    OwnedValue::try_from(value).expect("chuỗi luôn chuyển được sang OwnedValue")
}

fn string(settings: &Settings, setting: &str, key: &str) -> Option<String> {
    match &**settings.get(setting)?.get(key)? {
        Value::Str(s) => Some(s.to_string()),
        _ => None,
    }
}

fn bytes(settings: &Settings, setting: &str, key: &str) -> Option<Vec<u8>> {
    match &**settings.get(setting)?.get(key)? {
        Value::Array(array) => array
            .iter()
            .map(|v| match v {
                Value::U8(b) => Some(*b),
                _ => None,
            })
            .collect(),
        _ => None,
    }
}

pub struct SecretAgent {
    prompts: Arc<Prompts>,
    /// (đường dẫn kết nối, setting) → hộp thoại đang mở, để huỷ được.
    open: Mutex<HashMap<(String, String), u64>>,
}

impl SecretAgent {
    pub fn new(prompts: Arc<Prompts>) -> Self {
        Self {
            prompts,
            open: Mutex::new(HashMap::new()),
        }
    }
}

#[interface(name = "org.freedesktop.NetworkManager.SecretAgent")]
impl SecretAgent {
    async fn get_secrets(
        &self,
        connection: Settings,
        connection_path: OwnedObjectPath,
        setting_name: String,
        _hints: Vec<String>,
        flags: u32,
    ) -> Result<Settings, AgentError> {
        debug!("NetworkManager hỏi {setting_name} cho {connection_path} (cờ {flags:#x})");
        if flags & ALLOW_INTERACTION == 0 {
            return Err(AgentError::NoSecrets(
                "glassd không lưu mật khẩu, chỉ hỏi người dùng".into(),
            ));
        }
        let Some(request) = SecretRequest::parse(&connection, &setting_name) else {
            return Err(AgentError::NoSecrets(format!("glassd chưa hỗ trợ hỏi {setting_name}")));
        };

        let prompt = Prompt::WifiSecrets {
            ssid: request.ssid.clone(),
            security: request.security.into(),
            fields: request.fields.iter().map(|f| f.to_string()).collect(),
            retry: flags & REQUEST_NEW != 0,
        };
        let ticket = self.prompts.begin(prompt).await?;
        let key = (connection_path.to_string(), setting_name.clone());
        self.open.lock().await.insert(key.clone(), ticket.id);
        let answer = self.prompts.wait(ticket, TIMEOUT).await;
        self.open.lock().await.remove(&key);

        request.secrets(&setting_name, &answer?)
    }

    async fn cancel_get_secrets(&self, connection_path: OwnedObjectPath, setting_name: String) {
        let key = (connection_path.to_string(), setting_name);
        if let Some(id) = self.open.lock().await.remove(&key) {
            debug!("NetworkManager huỷ yêu cầu mật khẩu {id}");
            self.prompts.close(id, PromptError::Canceled).await;
        }
    }

    /// NetworkManager tự lưu mật khẩu theo cờ của kết nối; glassd không giữ gì.
    async fn save_secrets(&self, _connection: Settings, _connection_path: OwnedObjectPath) {}

    async fn delete_secrets(&self, _connection: Settings, _connection_path: OwnedObjectPath) {}
}

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager.AgentManager",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager/AgentManager"
)]
trait AgentManager {
    fn register_with_capabilities(&self, identifier: &str, capabilities: u32) -> zbus::Result<()>;
}

async fn register(system: &Connection) {
    let result = async {
        AgentManagerProxy::new(system)
            .await?
            .register_with_capabilities(IDENTIFIER, 0)
            .await
    }
    .await;
    match result {
        Ok(()) => info!("đã đăng ký agent mật khẩu với NetworkManager"),
        Err(e) => warn!("không đăng ký được agent với NetworkManager: {e}"),
    }
}

/// Đặt agent trên system bus và đăng ký với NetworkManager, cả mỗi lần
/// NetworkManager khởi động lại.
pub async fn run(system: Connection, prompts: Arc<Prompts>) -> anyhow::Result<()> {
    system.object_server().at(AGENT_PATH, SecretAgent::new(prompts)).await?;

    let bus = fdo::DBusProxy::new(&system).await?;
    let mut owners = bus.receive_name_owner_changed_with_args(&[(0, NM_NAME)]).await?;
    if bus.name_has_owner(NM_NAME.try_into()?).await? {
        register(&system).await;
    } else {
        info!("NetworkManager chưa chạy; sẽ đăng ký agent khi nó lên");
    }
    while let Some(signal) = owners.next().await {
        if signal.args()?.new_owner().is_some() {
            register(&system).await;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wifi(key_mgmt: Option<&str>) -> Settings {
        let mut settings = Settings::new();
        settings.insert(
            "connection".into(),
            HashMap::from([("id".to_string(), owned(Value::from("Nhà")))]),
        );
        settings.insert(
            "802-11-wireless".into(),
            HashMap::from([(
                "ssid".to_string(),
                owned(Value::from("Quán cà phê".as_bytes().to_vec())),
            )]),
        );
        if let Some(k) = key_mgmt {
            settings.insert(
                "802-11-wireless-security".into(),
                HashMap::from([("key-mgmt".to_string(), owned(Value::from(k)))]),
            );
        }
        settings
    }

    #[test]
    fn parses_wifi_requests() {
        let psk = SecretRequest::parse(&wifi(Some("wpa-psk")), "802-11-wireless-security").unwrap();
        assert_eq!(psk.ssid, "Quán cà phê");
        assert_eq!((psk.security, psk.fields), ("psk", &["psk"][..]));

        let sae = SecretRequest::parse(&wifi(Some("sae")), "802-11-wireless-security").unwrap();
        assert_eq!(sae.security, "psk");

        let wep = SecretRequest::parse(&wifi(Some("none")), "802-11-wireless-security").unwrap();
        assert_eq!(wep.fields, &["wep-key0"]);

        let eap = SecretRequest::parse(&wifi(Some("wpa-eap")), "802-1x").unwrap();
        assert_eq!(eap.fields, &["identity", "password"]);

        assert!(SecretRequest::parse(&wifi(Some("wpa-eap")), "802-11-wireless-security").is_none());
        assert!(SecretRequest::parse(&wifi(None), "vpn").is_none());
    }

    #[test]
    fn builds_reply() {
        let request = SecretRequest::parse(&wifi(Some("wpa-psk")), "802-11-wireless-security").unwrap();
        let answer = Answer::from([("psk".to_string(), "mat-khau-dai".to_string())]);
        let reply = request.secrets("802-11-wireless-security", &answer).unwrap();
        assert_eq!(
            string(&reply, "802-11-wireless-security", "psk").as_deref(),
            Some("mat-khau-dai")
        );
        assert!(request.secrets("802-11-wireless-security", &Answer::new()).is_err());
    }
}
