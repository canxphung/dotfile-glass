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
use tokio::sync::broadcast::error::RecvError;
use tracing::{debug, info, warn};

use crate::service::Service;

/// Dòng dài hơn mức này bị coi là lỗi giao thức.
const MAX_LINE: usize = 64 * 1024;

#[derive(Debug, Deserialize)]
struct Request {
    #[serde(default)]
    id: Value,
    method: String,
    key: Option<String>,
    value: Option<Scalar>,
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

pub async fn serve(service: Arc<Service>, listener: UnixListener) {
    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let service = service.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle(service, stream).await {
                        debug!("client socket ngắt: {e}");
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

async fn handle(service: Arc<Service>, stream: UnixStream) -> anyhow::Result<()> {
    let (read, mut write) = stream.into_split();
    let mut reader = BufReader::new(read);
    let mut events = service.subscribe();

    let hello = json!({
        "event": "hello",
        "version": env!("CARGO_PKG_VERSION"),
        "settings": service.get_all().await,
        "palettes": service.palettes(),
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
                let reply = respond(&service, line.trim()).await;
                send(&mut write, &reply).await?;
                line.clear();
            }
            event = events.recv() => match event {
                Ok(event) => send(&mut write, &serde_json::to_value(&event)?).await?,
                Err(RecvError::Lagged(n)) => warn!("client socket bỏ lỡ {n} sự kiện"),
                Err(RecvError::Closed) => return Ok(()),
            },
        }
    }
}

async fn respond(service: &Service, line: &str) -> Value {
    let request: Request = match serde_json::from_str(line) {
        Ok(r) => r,
        Err(e) => return json!({"ok": false, "error": format!("JSON không hợp lệ: {e}")}),
    };
    let id = request.id.clone();

    let need_key = || request.key.clone().ok_or_else(|| "thiếu \"key\"".to_string());
    let result: Result<Value, String> = match request.method.as_str() {
        "ping" => Ok(json!("pong")),
        "get_all" => Ok(json!(service.get_all().await)),
        "get" => match need_key() {
            Ok(key) => service.get(&key).await.map(|v| json!(v)).map_err(|e| e.to_string()),
            Err(e) => Err(e),
        },
        "set" => match (need_key(), request.value.clone()) {
            (Ok(key), Some(value)) => service
                .set(&key, value)
                .await
                .map(|()| Value::Null)
                .map_err(|e| e.to_string()),
            (Err(e), _) => Err(e),
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
        other => Err(format!("không có method {other:?}")),
    };

    match result {
        Ok(value) => json!({"id": id, "ok": true, "result": value}),
        Err(error) => json!({"id": id, "ok": false, "error": error}),
    }
}
