//! Kênh cho shell (Quickshell không gọi D-Bus tuỳ ý được): unix socket
//! `$XDG_RUNTIME_DIR/glass/glassd.sock`, mỗi dòng một JSON. Tài liệu:
//! docs/ipc.md.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::Arc;

use glass_core::settings::Scalar;
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::broadcast;
use tokio::sync::broadcast::error::RecvError;
use tracing::{debug, info, warn};

use crate::prompts::{Answer, PromptError, PromptEvent, Prompts};
use crate::service::Service;

/// Dòng dài hơn mức này bị coi là lỗi giao thức.
const MAX_LINE: usize = 64 * 1024;

#[derive(Debug, Deserialize)]
struct Request {
    #[serde(default)]
    id: Value,
    method: String,
    key: Option<String>,
    value: Option<Value>,
    /// id của hộp thoại, với prompt_reply và prompt_cancel.
    prompt: Option<u64>,
}

pub fn bind(path: &Path) -> anyhow::Result<UnixListener> {
    let dir = path.parent().expect("socket luôn nằm trong một thư mục");
    fs::create_dir_all(dir)?;
    fs::set_permissions(dir, fs::Permissions::from_mode(0o700))?;
    // Socket cũ còn sót từ lần chạy trước (glassd chỉ chạy một bản nhờ tên D-Bus).
    let _ = fs::remove_file(path);
    let listener = UnixListener::bind(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    info!("socket cho shell: {}", path.display());
    Ok(listener)
}

pub async fn serve(service: Arc<Service>, prompts: Arc<Prompts>, listener: UnixListener) {
    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let service = service.clone();
                let prompts = prompts.clone();
                tokio::spawn(async move {
                    let mut client = Client {
                        service,
                        prompts,
                        prompt_events: None,
                    };
                    if let Err(e) = client.handle(stream).await {
                        debug!("client socket ngắt: {e}");
                    }
                    if client.prompt_events.is_some() {
                        client.prompts.detach_ui();
                    }
                });
            }
            Err(e) => warn!("lỗi nhận kết nối socket: {e}"),
        }
    }
}

async fn send(writer: &mut (impl AsyncWriteExt + Unpin), value: &Value) -> std::io::Result<()> {
    let mut line = serde_json::to_string(value).expect("JSON luôn ghi được");
    line.push('\n');
    writer.write_all(line.as_bytes()).await
}

async fn next_prompt_event(rx: &mut Option<broadcast::Receiver<PromptEvent>>) -> Result<PromptEvent, RecvError> {
    match rx {
        Some(rx) => rx.recv().await,
        None => std::future::pending().await,
    }
}

struct Client {
    service: Arc<Service>,
    prompts: Arc<Prompts>,
    /// Có khi client đã nhận vai hiện hộp thoại (method handle_prompts).
    prompt_events: Option<broadcast::Receiver<PromptEvent>>,
}

impl Client {
    async fn handle(&mut self, stream: UnixStream) -> anyhow::Result<()> {
        let (read, mut write) = stream.into_split();
        let mut reader = BufReader::new(read);
        let mut events = self.service.subscribe();

        let hello = json!({
            "event": "hello",
            "version": env!("CARGO_PKG_VERSION"),
            "settings": self.service.get_all().await,
            "palettes": self.service.palettes(),
        });
        send(&mut write, &hello).await?;

        let mut line = String::new();
        loop {
            tokio::select! {
                read = reader.read_line(&mut line) => {
                    if read? == 0 {
                        return Ok(());
                    }
                    if line.len() > MAX_LINE {
                        send(&mut write, &json!({"ok": false, "error": "dòng quá dài"})).await?;
                        return Ok(());
                    }
                    let (reply, replay) = self.respond(line.trim()).await;
                    send(&mut write, &reply).await?;
                    for event in replay {
                        send(&mut write, &serde_json::to_value(&event)?).await?;
                    }
                    line.clear();
                }
                event = events.recv() => match event {
                    Ok(event) => send(&mut write, &serde_json::to_value(&event)?).await?,
                    Err(RecvError::Lagged(n)) => warn!("client socket bỏ lỡ {n} sự kiện"),
                    Err(RecvError::Closed) => return Ok(()),
                },
                event = next_prompt_event(&mut self.prompt_events) => match event {
                    Ok(event) => send(&mut write, &serde_json::to_value(&event)?).await?,
                    Err(RecvError::Lagged(n)) => warn!("client socket bỏ lỡ {n} hộp thoại"),
                    Err(RecvError::Closed) => return Ok(()),
                },
            }
        }
    }

    /// Trả lời một yêu cầu, kèm các sự kiện cần gửi ngay sau câu trả lời.
    async fn respond(&mut self, line: &str) -> (Value, Vec<PromptEvent>) {
        let request: Request = match serde_json::from_str(line) {
            Ok(r) => r,
            Err(e) => return (json!({"ok": false, "error": format!("JSON không hợp lệ: {e}")}), vec![]),
        };
        let id = request.id.clone();
        let service = &self.service;
        let mut replay = vec![];

        let need_key = || request.key.clone().ok_or_else(|| "thiếu \"key\"".to_string());
        let need_prompt = || request.prompt.ok_or_else(|| "thiếu \"prompt\"".to_string());
        let result: Result<Value, String> = match request.method.as_str() {
            "ping" => Ok(json!("pong")),
            "get_all" => Ok(json!(service.get_all().await)),
            "get" => match need_key() {
                Ok(key) => service.get(&key).await.map(|v| json!(v)).map_err(|e| e.to_string()),
                Err(e) => Err(e),
            },
            "set" => match (need_key(), request.value.clone().map(serde_json::from_value::<Scalar>)) {
                (Ok(key), Some(Ok(value))) => service
                    .set(&key, value)
                    .await
                    .map(|()| Value::Null)
                    .map_err(|e| e.to_string()),
                (Err(e), _) => Err(e),
                (_, Some(Err(_))) => Err("\"value\" phải là chuỗi, số hoặc true/false".into()),
                (_, None) => Err("thiếu \"value\"".into()),
            },
            "reset" => match need_key() {
                Ok(key) => service
                    .reset(&key)
                    .await
                    .map(|()| Value::Null)
                    .map_err(|e| e.to_string()),
                Err(e) => Err(e),
            },
            "palettes" => Ok(json!(service.palettes())),
            "reload" => service
                .reload_from_disk()
                .await
                .map(|()| Value::Null)
                .map_err(|e| e.to_string()),
            "handle_prompts" => {
                if self.prompt_events.is_none() {
                    // Đăng ký nhận trước khi lấy danh sách đang mở, để không
                    // lọt hộp thoại mở đúng lúc đó.
                    self.prompt_events = Some(self.prompts.subscribe());
                    replay = self.prompts.attach_ui().await;
                }
                Ok(Value::Null)
            }
            "prompt_reply" => match (
                need_prompt(),
                request.value.clone().map(serde_json::from_value::<Answer>),
            ) {
                (Ok(prompt), Some(Ok(answer))) => Ok(json!(self.prompts.answer(prompt, answer).await)),
                (Err(e), _) => Err(e),
                (_, Some(Err(_))) => Err("\"value\" phải là object chuỗi → chuỗi".into()),
                (_, None) => Err("thiếu \"value\"".into()),
            },
            "prompt_cancel" => match need_prompt() {
                Ok(prompt) => Ok(json!(self.prompts.close(prompt, PromptError::Canceled).await)),
                Err(e) => Err(e),
            },
            other => Err(format!("không có method {other:?}")),
        };

        let reply = match result {
            Ok(value) => json!({"id": id, "ok": true, "result": value}),
            Err(error) => json!({"id": id, "ok": false, "error": error}),
        };
        (reply, replay)
    }
}
