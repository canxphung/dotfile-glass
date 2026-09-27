//! Áp settings ra hệ thống: gsettings, Hyprland, kitty và các dịch vụ
//! user của phiên. Mọi lệnh đều chạy có giới hạn thời gian; lỗi chỉ ghi
//! log, không làm glassd dừng.

use std::collections::BTreeSet;
use std::env;
use std::os::unix::fs::MetadataExt;
use std::process::Stdio;
use std::time::Duration;

use glass_core::Paths;
use glass_core::render::{IDLE, NIGHT_LIGHT, THEME_HYPRLAND, THEME_KITTY, WALLPAPER};
use glass_core::settings::Settings;
use tokio::process::Command;
use tracing::{debug, warn};

const TIMEOUT: Duration = Duration::from_secs(10);
const GSETTINGS_SCHEMA: &str = "org.gnome.desktop.interface";

/// Những gì cần làm sau một lần đổi settings.
#[derive(Debug)]
pub struct Actions {
    settings: Settings,
    wallpaper: String,
    files: BTreeSet<&'static str>,
    keys: BTreeSet<String>,
    /// Áp lại mọi khoá gsettings (lúc khởi động).
    pub all_gsettings: bool,
    /// Lúc khởi động: đưa night light về đúng trạng thái bật/tắt.
    pub night_light: Option<bool>,
}

impl Actions {
    pub fn new(paths: &Paths, settings: &Settings) -> Self {
        let wallpaper = match settings.wallpaper.path.trim() {
            "" => paths.default_wallpaper(),
            path => paths.expand_home(path),
        };
        Self {
            settings: settings.clone(),
            wallpaper: wallpaper.to_string_lossy().into_owned(),
            files: BTreeSet::new(),
            keys: BTreeSet::new(),
            all_gsettings: false,
            night_light: None,
        }
    }

    pub fn note_file(&mut self, path: &'static str) {
        self.files.insert(path);
    }

    pub fn note_key(&mut self, key: &str) {
        self.keys.insert(key.to_string());
    }

    fn gsettings(&self) -> Vec<(&'static str, String)> {
        let a = &self.settings.appearance;
        let all = [
            (
                "appearance.color_scheme",
                "color-scheme",
                a.color_scheme.gsettings_value().to_string(),
            ),
            ("appearance.font", "font-name", a.font.clone()),
            (
                "appearance.monospace_font",
                "monospace-font-name",
                a.monospace_font.clone(),
            ),
        ];
        all.into_iter()
            .filter(|(key, _, _)| self.all_gsettings || self.keys.contains(*key))
            .map(|(_, gkey, value)| (gkey, value))
            .collect()
    }
}

pub async fn run(actions: &Actions) {
    let in_hyprland = env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some();

    for (key, value) in actions.gsettings() {
        run_cmd("gsettings", &["set", GSETTINGS_SCHEMA, key, &value]).await;
    }

    if actions.files.contains(THEME_HYPRLAND) && in_hyprland {
        run_cmd("hyprctl", &["reload"]).await;
    }

    if actions.files.contains(THEME_KITTY) {
        reload_kitty().await;
    }

    if actions.files.contains(IDLE) {
        // hypridle không tự đọc lại config; chỉ khởi động lại nếu đang chạy.
        run_cmd("systemctl", &["--user", "try-restart", "glass-idle.service"]).await;
    }

    if actions.files.contains(WALLPAPER) && in_hyprland {
        set_wallpaper(&actions.wallpaper, fit_name(&actions.settings)).await;
    }

    let enabled = actions.settings.night_light.enabled;
    let explicit = actions.night_light.is_some() || actions.keys.contains("night_light.enabled");
    if enabled {
        if actions.files.contains(NIGHT_LIGHT) {
            run_cmd("systemctl", &["--user", "restart", "glass-nightlight.service"]).await;
        } else if explicit {
            run_cmd("systemctl", &["--user", "start", "glass-nightlight.service"]).await;
        }
    } else if explicit {
        run_cmd("systemctl", &["--user", "stop", "glass-nightlight.service"]).await;
    }
}

fn fit_name(settings: &Settings) -> &'static str {
    use glass_core::settings::Fit;
    match settings.wallpaper.fit {
        Fit::Cover => "cover",
        Fit::Contain => "contain",
        Fit::Tile => "tile",
        Fit::Fill => "fill",
    }
}

async fn set_wallpaper(path: &str, fit: &str) {
    // Lệnh IPC của hyprpaper tách tham số bằng dấu phẩy; đường dẫn có dấu
    // phẩy thì khởi động lại hyprpaper để nó đọc file state mới.
    if path.contains(',') {
        run_cmd("systemctl", &["--user", "try-restart", "glass-wallpaper.service"]).await;
        return;
    }
    let arg = format!(",{path},{fit}");
    run_cmd("hyprctl", &["hyprpaper", "wallpaper", &arg]).await;
}

/// kitty đọc lại config (kể cả file include) khi nhận SIGUSR1.
async fn reload_kitty() {
    let Ok(uid) = std::fs::metadata("/proc/self").map(|m| m.uid()) else {
        return;
    };
    // pkill trả mã 1 khi không có kitty nào đang chạy: không phải lỗi.
    run_cmd_ok_codes("pkill", &["-USR1", "-x", "-U", &uid.to_string(), "kitty"], &[0, 1]).await;
}

async fn run_cmd(program: &str, args: &[&str]) -> bool {
    run_cmd_ok_codes(program, args, &[0]).await
}

async fn run_cmd_ok_codes(program: &str, args: &[&str], ok: &[i32]) -> bool {
    let output = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .output();

    match tokio::time::timeout(TIMEOUT, output).await {
        Ok(Ok(out)) if out.status.code().is_some_and(|c| ok.contains(&c)) => {
            debug!("{program} {args:?}: ok");
            true
        }
        Ok(Ok(out)) => {
            let stderr = String::from_utf8_lossy(&out.stderr);
            warn!("{program} {args:?} lỗi ({}): {}", out.status, stderr.trim());
            false
        }
        Ok(Err(e)) => {
            warn!("không chạy được {program}: {e}");
            false
        }
        Err(_) => {
            warn!("{program} {args:?} chạy quá {} giây", TIMEOUT.as_secs());
            false
        }
    }
}
