//! glassd: daemon settings của desktop Glass.
//!
//! - Giữ `~/.config/glass/settings.toml`, kiểm tra và ghi giữ comment.
//! - Render file theme/state vào `~/.local/state/glass` từ palette + settings.
//! - Áp ra hệ thống: gsettings, Hyprland, kitty, hypridle, hyprpaper, hyprsunset.
//! - API: D-Bus `io.github.canxphung.Glass1` và unix socket cho shell.
//!
//! Chạy bởi glassd.service trong phiên Glass.

mod apply;
mod dbus;
mod service;
mod socket;
mod watch;

use std::sync::Arc;

use anyhow::Context;
use glass_core::Paths;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

use crate::service::Service;

fn main() -> anyhow::Result<()> {
    if let Some(arg) = std::env::args().nth(1) {
        match arg.as_str() {
            "--version" | "-V" => {
                println!(
                    "glassd {} (dữ liệu: {})",
                    env!("CARGO_PKG_VERSION"),
                    glass_core::paths::DEFAULT_DATADIR
                );
                return Ok(());
            }
            "--help" | "-h" => {
                println!("glassd: daemon settings của Glass. Chạy bởi glassd.service; điều khiển bằng glassctl.");
                println!("Log chi tiết: GLASSD_LOG=debug glassd");
                return Ok(());
            }
            other => anyhow::bail!("tham số không rõ: {other}"),
        }
    }

    // journald đã ghi thời gian; không cần in thêm.
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_env("GLASSD_LOG").unwrap_or_else(|_| EnvFilter::new("info")))
        .with_ansi(false)
        .without_time()
        .with_target(false)
        .init();

    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build()?;
    runtime.block_on(run())
}

async fn run() -> anyhow::Result<()> {
    let paths = Paths::from_env().context("không xác định được thư mục")?;
    let service = Arc::new(Service::load(paths).context("không khởi động được")?);

    let conn = dbus::connect(service.clone())
        .await
        .context("không kết nối được session bus")?;
    if dbus::already_running(&conn).await? {
        anyhow::bail!("glassd đang chạy rồi");
    }

    // Render file state trước khi giữ tên D-Bus: systemd coi glassd sẵn
    // sàng khi có tên, và hypridle/hyprpaper chạy sau đó sẽ đọc được file.
    service.startup().await;
    dbus::claim_name(&conn)
        .await
        .context("không giữ được tên D-Bus (glassd đang chạy rồi?)")?;

    // Chỉ mở socket khi chắc chắn là bản duy nhất, để không xoá mất socket
    // của một glassd khác.
    let listener = socket::bind(&service.paths().socket())?;
    info!("glassd {} sẵn sàng", env!("CARGO_PKG_VERSION"));

    let watcher = tokio::spawn(watch::run(service.clone()));
    tokio::spawn(socket::serve(service.clone(), listener));

    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    tokio::select! {
        _ = term.recv() => info!("nhận SIGTERM, dừng"),
        _ = tokio::signal::ctrl_c() => info!("nhận SIGINT, dừng"),
        result = watcher => match result {
            Ok(Err(e)) => error!("bộ theo dõi settings.toml dừng: {e:#}"),
            _ => error!("bộ theo dõi settings.toml dừng bất thường"),
        },
    }

    let _ = std::fs::remove_file(service.paths().socket());
    Ok(())
}
