//! Test agent Wi-Fi và Bluetooth trên một bus D-Bus riêng (dbus-daemon),
//! với NetworkManager và BlueZ giả chạy ngay trong test. Không có
//! dbus-daemon thì bỏ qua.

use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::Mutex;
use zbus::message::Header;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::{Connection, interface};

use crate::prompts::{Answer, PromptEvent, Prompts};
use crate::{bt_agent, nm_agent};

struct Bus {
    child: Child,
    address: String,
}

impl Bus {
    fn start() -> Option<Self> {
        let mut child = Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--print-address=1"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .ok()?;
        let mut address = String::new();
        BufReader::new(child.stdout.take()?).read_line(&mut address).ok()?;
        Some(Self {
            child,
            address: address.trim().to_string(),
        })
    }

    async fn connect(&self) -> Connection {
        zbus::connection::Builder::address(self.address.as_str())
            .unwrap()
            .build()
            .await
            .unwrap()
    }
}

impl Drop for Bus {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

macro_rules! bus_or_skip {
    () => {
        match Bus::start() {
            Some(bus) => bus,
            None => {
                eprintln!("bỏ qua: không chạy được dbus-daemon");
                return;
            }
        }
    };
}

/// Chờ tới khi điều kiện đúng, tối đa 5 giây.
async fn eventually(mut check: impl AsyncFnMut() -> bool) {
    for _ in 0..100 {
        if check().await {
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("hết giờ chờ");
}

/// Người dùng giả: nhận vai hiện hộp thoại.
async fn ui(prompts: &Prompts) -> tokio::sync::broadcast::Receiver<PromptEvent> {
    let events = prompts.subscribe();
    prompts.attach_ui().await;
    events
}

async fn next_prompt(events: &mut tokio::sync::broadcast::Receiver<PromptEvent>) -> (u64, serde_json::Value) {
    loop {
        let event = tokio::time::timeout(Duration::from_secs(5), events.recv())
            .await
            .expect("hết giờ chờ hộp thoại")
            .unwrap();
        if let PromptEvent::Prompt { id, .. } = &event {
            return (*id, serde_json::to_value(&event).unwrap());
        }
    }
}

fn error_name(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(name, _, _) => name.to_string(),
        other => panic!("cần lỗi D-Bus có tên, nhận {other:?}"),
    }
}

// ---- NetworkManager ----

#[derive(Clone, Default)]
struct FakeAgentManager {
    /// (tên unique của agent, identifier) theo thứ tự đăng ký.
    registered: Arc<Mutex<Vec<(String, String)>>>,
}

#[interface(name = "org.freedesktop.NetworkManager.AgentManager")]
impl FakeAgentManager {
    async fn register_with_capabilities(&self, #[zbus(header)] header: Header<'_>, identifier: String, _caps: u32) {
        let sender = header.sender().unwrap().to_string();
        self.registered.lock().await.push((sender, identifier));
    }
}

fn wifi_settings() -> nm_agent::Settings {
    let owned = |v: Value<'_>| OwnedValue::try_from(v).unwrap();
    HashMap::from([
        (
            "connection".to_string(),
            HashMap::from([("id".to_string(), owned(Value::from("Nhà")))]),
        ),
        (
            "802-11-wireless".to_string(),
            HashMap::from([("ssid".to_string(), owned(Value::from(b"Tang 2".to_vec())))]),
        ),
        (
            "802-11-wireless-security".to_string(),
            HashMap::from([("key-mgmt".to_string(), owned(Value::from("wpa-psk")))]),
        ),
    ])
}

async fn get_secrets(nm: &Connection, agent: &str, flags: u32) -> zbus::Result<nm_agent::Settings> {
    let proxy = zbus::Proxy::new(
        nm,
        agent.to_string(),
        nm_agent::AGENT_PATH,
        "org.freedesktop.NetworkManager.SecretAgent",
    )
    .await?;
    let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/7").unwrap();
    proxy
        .call(
            "GetSecrets",
            &(
                wifi_settings(),
                path,
                "802-11-wireless-security",
                Vec::<String>::new(),
                flags,
            ),
        )
        .await
}

#[tokio::test]
async fn nm_agent_registers_and_answers() {
    let bus = bus_or_skip!();
    let nm = bus.connect().await;
    let manager = FakeAgentManager::default();
    nm.object_server()
        .at("/org/freedesktop/NetworkManager/AgentManager", manager.clone())
        .await
        .unwrap();
    nm.request_name("org.freedesktop.NetworkManager").await.unwrap();

    let system = bus.connect().await;
    let agent = system.unique_name().unwrap().to_string();
    let prompts = Arc::new(Prompts::default());
    tokio::spawn(nm_agent::run(system.clone(), prompts.clone()));
    eventually(async || manager.registered.lock().await.len() == 1).await;
    assert_eq!(
        manager.registered.lock().await[0],
        (agent.clone(), "io.github.canxphung.glass".to_string())
    );

    // Chưa có shell: không hỏi được.
    let e = get_secrets(&nm, &agent, 1).await.unwrap_err();
    assert_eq!(error_name(&e), "org.freedesktop.NetworkManager.SecretAgent.NoSecrets");

    // Có shell: hỏi, người dùng gõ mật khẩu, NetworkManager nhận được.
    let mut events = ui(&prompts).await;
    let call = {
        let nm = nm.clone();
        let agent = agent.clone();
        tokio::spawn(async move { get_secrets(&nm, &agent, 1 | 2).await })
    };
    let (id, event) = next_prompt(&mut events).await;
    assert_eq!(event["kind"], "wifi_secrets");
    assert_eq!(event["ssid"], "Tang 2");
    assert_eq!(event["fields"], serde_json::json!(["psk"]));
    assert_eq!(event["retry"], true, "cờ REQUEST_NEW: mật khẩu cũ sai");
    prompts
        .answer(id, Answer::from([("psk".to_string(), "12345678".to_string())]))
        .await;
    let secrets = call.await.unwrap().unwrap();
    let psk = &secrets["802-11-wireless-security"]["psk"];
    assert_eq!(**psk, Value::from("12345678"));

    // Không cho tương tác (NetworkManager tự kết nối lúc khởi động): không hỏi.
    let e = get_secrets(&nm, &agent, 0).await.unwrap_err();
    assert_eq!(error_name(&e), "org.freedesktop.NetworkManager.SecretAgent.NoSecrets");

    // NetworkManager huỷ giữa chừng: hộp thoại đóng, GetSecrets báo huỷ.
    let call = {
        let nm = nm.clone();
        let agent = agent.clone();
        tokio::spawn(async move { get_secrets(&nm, &agent, 1).await })
    };
    let (id, _) = next_prompt(&mut events).await;
    let proxy = zbus::Proxy::new(
        &nm,
        agent.clone(),
        nm_agent::AGENT_PATH,
        "org.freedesktop.NetworkManager.SecretAgent",
    )
    .await
    .unwrap();
    let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/7").unwrap();
    let () = proxy
        .call("CancelGetSecrets", &(path, "802-11-wireless-security"))
        .await
        .unwrap();
    let e = call.await.unwrap().unwrap_err();
    assert_eq!(
        error_name(&e),
        "org.freedesktop.NetworkManager.SecretAgent.UserCanceled"
    );
    assert!(!prompts.answer(id, Answer::new()).await, "hộp thoại phải đã đóng");

    // NetworkManager khởi động lại: agent đăng ký lại.
    nm.release_name("org.freedesktop.NetworkManager").await.unwrap();
    nm.request_name("org.freedesktop.NetworkManager").await.unwrap();
    eventually(async || manager.registered.lock().await.len() == 2).await;
}

// ---- BlueZ ----

#[derive(Clone, Default)]
struct FakeBluez {
    calls: Arc<Mutex<Vec<String>>>,
}

#[interface(name = "org.bluez.AgentManager1")]
impl FakeBluez {
    async fn register_agent(&self, agent: OwnedObjectPath, capability: String) {
        self.calls.lock().await.push(format!("register {agent} {capability}"));
    }

    async fn request_default_agent(&self, agent: OwnedObjectPath) {
        self.calls.lock().await.push(format!("default {agent}"));
    }
}

struct FakeDevice;

#[interface(name = "org.bluez.Device1")]
impl FakeDevice {
    #[zbus(property)]
    async fn alias(&self) -> String {
        "Tai nghe".into()
    }
}

const DEVICE: &str = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF";

async fn confirm(bluez: &Connection, agent: &str) -> zbus::Result<()> {
    let proxy = zbus::Proxy::new(bluez, agent.to_string(), bt_agent::AGENT_PATH, "org.bluez.Agent1").await?;
    proxy
        .call(
            "RequestConfirmation",
            &(ObjectPath::try_from(DEVICE).unwrap(), 123_456u32),
        )
        .await
}

#[tokio::test]
async fn bluetooth_agent_confirms_pairing() {
    let bus = bus_or_skip!();
    let bluez = bus.connect().await;
    let fake = FakeBluez::default();
    bluez.object_server().at("/org/bluez", fake.clone()).await.unwrap();
    bluez.object_server().at(DEVICE, FakeDevice).await.unwrap();
    bluez.request_name("org.bluez").await.unwrap();

    let system = bus.connect().await;
    let agent = system.unique_name().unwrap().to_string();
    let prompts = Arc::new(Prompts::default());
    tokio::spawn(bt_agent::run(system.clone(), prompts.clone()));
    eventually(async || fake.calls.lock().await.len() == 2).await;
    assert_eq!(
        *fake.calls.lock().await,
        vec![
            format!("register {} KeyboardDisplay", bt_agent::AGENT_PATH),
            format!("default {}", bt_agent::AGENT_PATH),
        ]
    );

    let mut events = ui(&prompts).await;

    // Mã khớp, người dùng đồng ý.
    let call = {
        let bluez = bluez.clone();
        let agent = agent.clone();
        tokio::spawn(async move { confirm(&bluez, &agent).await })
    };
    let (id, event) = next_prompt(&mut events).await;
    assert_eq!(event["kind"], "bluetooth");
    assert_eq!(event["action"], "confirm");
    assert_eq!(event["name"], "Tai nghe");
    assert_eq!(event["code"], "123456");
    assert_eq!(event["device"], DEVICE);
    prompts
        .answer(id, Answer::from([("accept".to_string(), "true".to_string())]))
        .await;
    call.await.unwrap().unwrap();

    // Người dùng từ chối.
    let call = {
        let bluez = bluez.clone();
        let agent = agent.clone();
        tokio::spawn(async move { confirm(&bluez, &agent).await })
    };
    let (id, _) = next_prompt(&mut events).await;
    prompts
        .answer(id, Answer::from([("accept".to_string(), "false".to_string())]))
        .await;
    let e = call.await.unwrap().unwrap_err();
    assert_eq!(error_name(&e), "org.bluez.Error.Rejected");

    // bluetoothd huỷ giữa chừng (thiết bị hết giờ chờ).
    let call = {
        let bluez = bluez.clone();
        let agent = agent.clone();
        tokio::spawn(async move { confirm(&bluez, &agent).await })
    };
    next_prompt(&mut events).await;
    let proxy = zbus::Proxy::new(&bluez, agent.clone(), bt_agent::AGENT_PATH, "org.bluez.Agent1")
        .await
        .unwrap();
    let () = proxy.call("Cancel", &()).await.unwrap();
    let e = call.await.unwrap().unwrap_err();
    assert_eq!(error_name(&e), "org.bluez.Error.Canceled");
}
