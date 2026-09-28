//! Agent ghép nối của BlueZ (org.bluez.Agent1).
//!
//! Khi ghép nối cần người dùng xác nhận mã, nhập PIN, hay cho phép một thiết
//! bị kết nối, bluetoothd hỏi agent mặc định. glassd đăng ký agent đó trên
//! system bus và chuyển câu hỏi sang shell (xem prompts.rs).

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use futures_util::StreamExt;
use tokio::sync::Mutex;
use tracing::{debug, info, warn};
use zbus::zvariant::{ObjectPath, OwnedObjectPath};
use zbus::{Connection, fdo, interface};

use crate::prompts::{Answer, Prompt, PromptError, Prompts};

pub const AGENT_PATH: &str = "/io/github/canxphung/Glass1/BluetoothAgent";
const BLUEZ_NAME: &str = "org.bluez";
/// Agent vừa hiện mã vừa nhận nhập, đủ cho mọi cách ghép nối.
const CAPABILITY: &str = "KeyboardDisplay";
const TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.bluez.Error")]
pub enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
    Canceled(String),
}

impl From<PromptError> for AgentError {
    fn from(e: PromptError) -> Self {
        match e {
            PromptError::Canceled | PromptError::Timeout => Self::Canceled(e.to_string()),
            PromptError::NoUi => Self::Rejected(e.to_string()),
        }
    }
}

/// Tên dễ đọc của vài dịch vụ hay gặp khi thiết bị xin kết nối.
fn service_name(uuid: &str) -> Option<&'static str> {
    let short = uuid.get(4..8)?;
    Some(match short.to_ascii_lowercase().as_str() {
        "110a" | "110b" | "110d" => "âm thanh (A2DP)",
        "110c" | "110e" | "110f" => "điều khiển phát nhạc (AVRCP)",
        "1108" | "1112" | "111e" | "111f" => "đàm thoại",
        "1124" => "bàn phím, chuột (HID)",
        "1105" => "gửi file (OPP)",
        "1106" => "truyền file (FTP)",
        "1115" | "1116" => "chia sẻ mạng (PAN)",
        "112f" => "danh bạ (PBAP)",
        "1132" => "tin nhắn (MAP)",
        _ => return None,
    })
}

fn accepted(answer: &Answer) -> bool {
    answer.get("accept").map(String::as_str) == Some("true")
}

pub struct BluetoothAgent {
    system: Connection,
    prompts: Arc<Prompts>,
    /// Thiết bị → hộp thoại "hãy nhập mã này trên thiết bị" đang mở.
    shown: Mutex<HashMap<String, u64>>,
}

impl BluetoothAgent {
    pub fn new(system: Connection, prompts: Arc<Prompts>) -> Self {
        Self {
            system,
            prompts,
            shown: Mutex::new(HashMap::new()),
        }
    }

    /// Tên thiết bị (Alias), hoặc địa chỉ nếu không đọc được.
    async fn name(&self, device: &ObjectPath<'_>) -> String {
        let alias = async {
            let props = fdo::PropertiesProxy::builder(&self.system)
                .destination(BLUEZ_NAME)?
                .path(device.to_owned())?
                .build()
                .await?;
            let value = props.get("org.bluez.Device1".try_into()?, "Alias").await?;
            Ok::<_, zbus::Error>(String::try_from(value)?)
        }
        .await;
        alias.unwrap_or_else(|_| {
            device
                .rsplit('/')
                .next()
                .and_then(|s| s.strip_prefix("dev_"))
                .map(|s| s.replace('_', ":"))
                .unwrap_or_else(|| device.to_string())
        })
    }

    async fn ask(
        &self,
        action: &str,
        device: &OwnedObjectPath,
        code: Option<String>,
        service: Option<String>,
    ) -> Result<Answer, AgentError> {
        self.close_shown(device).await;
        let prompt = Prompt::Bluetooth {
            action: action.into(),
            device: device.to_string(),
            name: self.name(device).await,
            code,
            service,
        };
        Ok(self.prompts.ask(prompt, TIMEOUT).await?)
    }

    async fn confirm(
        &self,
        action: &str,
        device: &OwnedObjectPath,
        code: Option<String>,
        service: Option<String>,
    ) -> Result<(), AgentError> {
        let answer = self.ask(action, device, code, service).await?;
        if accepted(&answer) {
            Ok(())
        } else {
            Err(AgentError::Rejected("người dùng từ chối".into()))
        }
    }

    async fn show(&self, action: &str, device: &OwnedObjectPath, code: String) {
        self.close_shown(device).await;
        let prompt = Prompt::Bluetooth {
            action: action.into(),
            device: device.to_string(),
            name: self.name(device).await,
            code: Some(code),
            service: None,
        };
        match self.prompts.show(prompt).await {
            Ok(id) => {
                self.shown.lock().await.insert(device.to_string(), id);
            }
            Err(e) => warn!("không hiện được mã ghép nối: {e}"),
        }
    }

    async fn close_shown(&self, device: &OwnedObjectPath) {
        if let Some(id) = self.shown.lock().await.remove(device.as_str()) {
            self.prompts.close(id, PromptError::Canceled).await;
        }
    }

    async fn close_all(&self) {
        self.shown.lock().await.clear();
        self.prompts
            .close_where(PromptError::Canceled, |p| matches!(p, Prompt::Bluetooth { .. }))
            .await;
    }
}

#[interface(name = "org.bluez.Agent1")]
impl BluetoothAgent {
    async fn release(&self) {
        debug!("bluetoothd bỏ agent");
        self.close_all().await;
    }

    async fn request_pin_code(&self, device: OwnedObjectPath) -> Result<String, AgentError> {
        let answer = self.ask("pin", &device, None, None).await?;
        match answer.get("value") {
            Some(pin) if (1..=16).contains(&pin.len()) => Ok(pin.clone()),
            _ => Err(AgentError::Rejected("PIN phải dài 1–16 ký tự".into())),
        }
    }

    async fn display_pin_code(&self, device: OwnedObjectPath, pincode: String) {
        self.show("display_pin", &device, pincode).await;
    }

    async fn request_passkey(&self, device: OwnedObjectPath) -> Result<u32, AgentError> {
        let answer = self.ask("passkey", &device, None, None).await?;
        answer
            .get("value")
            .and_then(|v| v.parse::<u32>().ok())
            .filter(|v| *v <= 999_999)
            .ok_or_else(|| AgentError::Rejected("mã phải là số 0–999999".into()))
    }

    async fn display_passkey(&self, device: OwnedObjectPath, passkey: u32, _entered: u16) {
        self.show("display_passkey", &device, format!("{passkey:06}")).await;
    }

    async fn request_confirmation(&self, device: OwnedObjectPath, passkey: u32) -> Result<(), AgentError> {
        self.confirm("confirm", &device, Some(format!("{passkey:06}")), None)
            .await
    }

    async fn request_authorization(&self, device: OwnedObjectPath) -> Result<(), AgentError> {
        self.confirm("authorize", &device, None, None).await
    }

    async fn authorize_service(&self, device: OwnedObjectPath, uuid: String) -> Result<(), AgentError> {
        let service = service_name(&uuid).map(str::to_string).unwrap_or(uuid);
        self.confirm("authorize_service", &device, None, Some(service)).await
    }

    async fn cancel(&self) {
        debug!("bluetoothd huỷ yêu cầu đang chờ");
        self.close_all().await;
    }
}

#[zbus::proxy(
    interface = "org.bluez.AgentManager1",
    default_service = "org.bluez",
    default_path = "/org/bluez"
)]
trait AgentManager1 {
    fn register_agent(&self, agent: &ObjectPath<'_>, capability: &str) -> zbus::Result<()>;
    fn request_default_agent(&self, agent: &ObjectPath<'_>) -> zbus::Result<()>;
}

async fn register(system: &Connection) {
    let result = async {
        let manager = AgentManager1Proxy::new(system).await?;
        let path = ObjectPath::try_from(AGENT_PATH)?;
        manager.register_agent(&path, CAPABILITY).await?;
        manager.request_default_agent(&path).await
    }
    .await;
    match result {
        Ok(()) => info!("đã đăng ký agent ghép nối với BlueZ"),
        Err(e) => warn!("không đăng ký được agent với BlueZ: {e}"),
    }
}

/// Đặt agent trên system bus và đăng ký với BlueZ, cả mỗi lần bluetoothd
/// khởi động lại.
pub async fn run(system: Connection, prompts: Arc<Prompts>) -> anyhow::Result<()> {
    system
        .object_server()
        .at(AGENT_PATH, BluetoothAgent::new(system.clone(), prompts))
        .await?;

    let bus = fdo::DBusProxy::new(&system).await?;
    let mut owners = bus.receive_name_owner_changed_with_args(&[(0, BLUEZ_NAME)]).await?;
    if bus.name_has_owner(BLUEZ_NAME.try_into()?).await? {
        register(&system).await;
    } else {
        info!("bluetoothd chưa chạy; sẽ đăng ký agent khi nó lên");
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

    #[test]
    fn names_common_services() {
        assert_eq!(
            service_name("0000110b-0000-1000-8000-00805f9b34fb"),
            Some("âm thanh (A2DP)")
        );
        assert_eq!(
            service_name("00001124-0000-1000-8000-00805F9B34FB"),
            Some("bàn phím, chuột (HID)")
        );
        assert_eq!(service_name("0000ffff-0000-1000-8000-00805f9b34fb"), None);
        assert_eq!(service_name("ngắn"), None);
    }
}
