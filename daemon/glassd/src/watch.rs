//! Theo dõi settings.toml: sửa tay và lưu là glassd áp ngay.

use std::sync::Arc;
use std::time::Duration;

use notify::{EventKind, RecursiveMode, Watcher};
use tokio::sync::mpsc;
use tracing::{debug, warn};

use crate::service::Service;

/// Trình soạn thảo thường ghi nhiều lần liên tiếp; gom lại rồi mới đọc.
const DEBOUNCE: Duration = Duration::from_millis(250);

pub async fn run(service: Arc<Service>) -> anyhow::Result<()> {
    let file = service.paths().settings_file();
    let dir = file
        .parent()
        .expect("settings.toml luôn nằm trong một thư mục")
        .to_path_buf();

    let (tx, mut rx) = mpsc::unbounded_channel();
    let target = file.clone();
    // Theo dõi cả thư mục: nhiều trình soạn thảo lưu bằng cách ghi file mới
    // rồi đổi tên đè lên file cũ.
    let mut watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| match res {
        Ok(event) => {
            let relevant = matches!(event.kind, EventKind::Create(_) | EventKind::Modify(_))
                && event.paths.iter().any(|p| p == &target);
            if relevant {
                let _ = tx.send(());
            }
        }
        Err(e) => warn!("lỗi theo dõi file: {e}"),
    })?;
    watcher.watch(&dir, RecursiveMode::NonRecursive)?;
    debug!("theo dõi {}", file.display());

    while rx.recv().await.is_some() {
        // Chờ cho đợt ghi kết thúc, bỏ các sự kiện dồn trong lúc chờ.
        tokio::time::sleep(DEBOUNCE).await;
        while rx.try_recv().is_ok() {}
        // Lỗi đã được ghi log và báo qua sự kiện FileError.
        let _ = service.reload_from_disk().await;
    }

    drop(watcher);
    Ok(())
}
