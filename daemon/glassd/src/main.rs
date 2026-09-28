//! glassd: daemon settings của desktop Glass.
//!
//! - Giữ `~/.config/glass/settings.toml`, kiểm tra và ghi giữ comment.
//! - Render file theme/state vào `~/.local/state/glass` từ palette + settings.
//! - Áp ra hệ thống: gsettings, Hyprland, kitty, hypridle, hyprpaper, hyprsunset.
//! - API: D-Bus `io.github.canxphung.Glass1` và unix socket cho shell.
//! - Agent mật khẩu Wi-Fi (NetworkManager) và ghép nối Bluetooth (BlueZ)
//!   trên system bus; hộp thoại do shell hiện qua socket.
//!
//! Chạy bởi glassd.service trong phiên Glass.

#[cfg(test)]
mod agent_tests;
mod apply;
mod bt_agent;
mod dbus;
mod nm_agent;
mod prompts;
mod service;
mod socket;
mod watch;

use std::sync::Arc;

use anyhow::Context;
use glass_core::Paths;
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

use crate::prompts::Prompts;
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

    let prompts = Arc::new(Prompts::default());
    let watcher = tokio::spawn(watch::run(service.clone()));
    tokio::spawn(socket::serve(service.clone(), prompts.clone(), listener));
    start_agents(prompts).await;

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

/// Agent Wi-Fi và Bluetooth. Không có system bus (vd. trong container) thì
/// glassd vẫn chạy, chỉ là không có hộp thoại mật khẩu/ghép nối.
async fn start_agents(prompts: Arc<Prompts>) {
    if std::env::var_os("GLASSD_NO_AGENTS").is_some() {
        info!("GLASSD_NO_AGENTS: không đăng ký agent Wi-Fi/Bluetooth");
        return;
    }
    let system = match zbus::Connection::system().await {
        Ok(system) => system,
        Err(e) => {
            warn!("không kết nối được system bus, không có agent Wi-Fi/Bluetooth: {e}");
            return;
        }
    };
    let agents = [
        ("Wi-Fi", tokio::spawn(nm_agent::run(system.clone(), prompts.clone()))),
        ("Bluetooth", tokio::spawn(bt_agent::run(system, prompts))),
    ];
    for (name, task) in agents {
        tokio::spawn(async move {
            match task.await {
                Ok(Err(e)) => warn!("agent {name} dừng: {e:#}"),
                Err(e) => warn!("agent {name} dừng bất thường: {e}"),
                Ok(Ok(())) => {}
            }
        });
    }
}
