//! Các thư mục Glass dùng, lấy theo biến môi trường XDG.

use std::env;
use std::path::{Path, PathBuf};

/// Thư mục dữ liệu mặc định. Makefile truyền `GLASS_DATADIR` lúc build để
/// khớp với prefix cài đặt; biến môi trường cùng tên đè lên lúc chạy.
pub const DEFAULT_DATADIR: &str = match option_env!("GLASS_DATADIR") {
    Some(dir) => dir,
    None => "/usr/share/glass",
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    /// Mặc định do gói quản lý, vd. `/usr/share/glass`.
    pub datadir: PathBuf,
    /// Config của người dùng, vd. `~/.config/glass`.
    pub config_dir: PathBuf,
    /// File glassd sinh ra, vd. `~/.local/state/glass`.
    pub state_dir: PathBuf,
    /// Dữ liệu riêng của người dùng, vd. `~/.local/share/glass` (palette tự làm).
    pub data_home: PathBuf,
    /// Socket và file tạm của phiên, vd. `/run/user/1000/glass`.
    pub runtime_dir: PathBuf,
    pub home: PathBuf,
}

#[derive(Debug, thiserror::Error)]
pub enum PathsError {
    #[error("biến môi trường {0} chưa được đặt")]
    MissingEnv(&'static str),
}

fn xdg(var: &str, home: &Path, fallback: &str) -> PathBuf {
    match env::var_os(var) {
        Some(value) if !value.is_empty() => PathBuf::from(value),
        _ => home.join(fallback),
    }
}

impl Paths {
    pub fn from_env() -> Result<Self, PathsError> {
        let home = PathBuf::from(env::var_os("HOME").ok_or(PathsError::MissingEnv("HOME"))?);
        let datadir = env::var_os("GLASS_DATADIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_DATADIR));
        let runtime = env::var_os("XDG_RUNTIME_DIR").ok_or(PathsError::MissingEnv("XDG_RUNTIME_DIR"))?;

        Ok(Self {
            datadir,
            config_dir: xdg("XDG_CONFIG_HOME", &home, ".config").join("glass"),
            state_dir: xdg("XDG_STATE_HOME", &home, ".local/state").join("glass"),
            data_home: xdg("XDG_DATA_HOME", &home, ".local/share").join("glass"),
            runtime_dir: PathBuf::from(runtime).join("glass"),
            home,
        })
    }

    pub fn settings_file(&self) -> PathBuf {
        self.config_dir.join("settings.toml")
    }

    /// Bản mẫu settings.toml có comment, chép ra khi người dùng chưa có.
    pub fn settings_template(&self) -> PathBuf {
        self.datadir.join("settings.toml")
    }

    pub fn templates_dir(&self) -> PathBuf {
        self.datadir.join("templates")
    }

    /// Thư mục palette, ưu tiên palette của người dùng.
    pub fn palette_dirs(&self) -> [PathBuf; 2] {
        [self.data_home.join("palettes"), self.datadir.join("palettes")]
    }

    pub fn default_wallpaper(&self) -> PathBuf {
        self.datadir.join("wallpapers/aero-sky.jpg")
    }

    pub fn socket(&self) -> PathBuf {
        self.runtime_dir.join("glassd.sock")
    }

    /// Mở rộng `~/` theo thư mục home.
    pub fn expand_home(&self, path: &str) -> PathBuf {
        match path.strip_prefix("~/") {
            Some(rest) => self.home.join(rest),
            None if path == "~" => self.home.clone(),
            None => PathBuf::from(path),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Paths {
        Paths {
            datadir: "/usr/share/glass".into(),
            config_dir: "/home/u/.config/glass".into(),
            state_dir: "/home/u/.local/state/glass".into(),
            data_home: "/home/u/.local/share/glass".into(),
            runtime_dir: "/run/user/1000/glass".into(),
            home: "/home/u".into(),
        }
    }

    #[test]
    fn expands_home() {
        let p = sample();
        assert_eq!(
            p.expand_home("~/Pictures/a.jpg"),
            PathBuf::from("/home/u/Pictures/a.jpg")
        );
        assert_eq!(p.expand_home("/abs/b.png"), PathBuf::from("/abs/b.png"));
        assert_eq!(p.expand_home("~"), PathBuf::from("/home/u"));
    }
}
