//! Palette màu Aero: đọc từ `palettes/<tên>.toml`, kiểm tra từng màu.

use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::paths::Paths;
use crate::settings::valid_name;

/// Màu dạng `#rrggbb`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Color(String);

impl Color {
    pub fn parse(text: &str) -> Result<Self, String> {
        let hex = text
            .strip_prefix('#')
            .ok_or_else(|| format!("màu {text:?} phải bắt đầu bằng #"))?;
        if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(format!("màu {text:?} phải có dạng #rrggbb"));
        }
        Ok(Self(format!("#{}", hex.to_ascii_lowercase())))
    }

    /// `rrggbb`, không có dấu #.
    pub fn hex(&self) -> &str {
        &self.0[1..]
    }
}

impl fmt::Display for Color {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Serialize for Color {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.0)
    }
}

impl<'de> Deserialize<'de> for Color {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let text = String::deserialize(d)?;
        Color::parse(&text).map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Palette {
    pub name: String,
    pub display_name: String,
    pub glass: Glass,
    pub text: Text,
    pub surface: Surface,
    pub accent: Accent,
    pub state: State,
    pub terminal: Terminal,
    pub shape: Shape,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Glass {
    pub tint: Color,
    pub tint_light: Color,
    pub tint_deep: Color,
    pub inactive_light: Color,
    pub inactive_deep: Color,
    pub edge: Color,
    pub highlight: Color,
    pub shadow: Color,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Text {
    pub on_glass: Color,
    pub on_dark: Color,
    pub muted: Color,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Surface {
    pub dark: Color,
    pub light: Color,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Accent {
    pub normal: Color,
    pub bright: Color,
    pub selection: Color,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct State {
    pub danger: Color,
    pub warning: Color,
    pub success: Color,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Terminal {
    pub foreground: Color,
    pub background: Color,
    pub cursor: Color,
    /// ANSI 0-7.
    pub normal: [Color; 8],
    /// ANSI 8-15.
    pub bright: [Color; 8],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Shape {
    pub radius: u32,
    pub border: u32,
    pub blur_size: u32,
    pub blur_passes: u32,
}

#[derive(Debug, thiserror::Error)]
pub enum PaletteError {
    #[error("tên palette không hợp lệ: {0:?}")]
    BadName(String),
    #[error("không tìm thấy palette {0:?}")]
    NotFound(String),
    #[error("không đọc được {path}: {reason}")]
    Load { path: PathBuf, reason: String },
}

impl Palette {
    pub fn from_file(path: &Path) -> Result<Self, PaletteError> {
        let load_err = |reason: String| PaletteError::Load {
            path: path.to_path_buf(),
            reason,
        };
        let text = fs::read_to_string(path).map_err(|e| load_err(e.to_string()))?;
        let palette: Palette = toml::from_str(&text).map_err(|e| load_err(e.to_string()))?;

        let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or_default();
        if palette.name != stem {
            return Err(load_err(format!(
                "name = {:?} phải trùng tên file ({stem:?})",
                palette.name
            )));
        }
        if !(1..=10).contains(&palette.shape.blur_passes) {
            return Err(load_err("shape.blur_passes phải trong khoảng 1..10".into()));
        }
        Ok(palette)
    }

    /// Tìm palette theo tên, ưu tiên thư mục của người dùng.
    pub fn load(paths: &Paths, name: &str) -> Result<Self, PaletteError> {
        if !valid_name(name) {
            return Err(PaletteError::BadName(name.into()));
        }
        for dir in paths.palette_dirs() {
            let file = dir.join(format!("{name}.toml"));
            if file.is_file() {
                return Self::from_file(&file);
            }
        }
        Err(PaletteError::NotFound(name.into()))
    }
}

/// Tên mọi palette có thể chọn, đã sắp xếp, không trùng.
pub fn list(paths: &Paths) -> Vec<String> {
    let mut names: Vec<String> = paths
        .palette_dirs()
        .iter()
        .filter_map(|dir| fs::read_dir(dir).ok())
        .flatten()
        .filter_map(|entry| {
            let path = entry.ok()?.path();
            (path.extension()? == "toml").then_some(())?;
            let stem = path.file_stem()?.to_str()?.to_string();
            valid_name(&stem).then_some(stem)
        })
        .collect();
    names.sort();
    names.dedup();
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo_palettes() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../theme/palettes")
    }

    #[test]
    fn shipped_palettes_are_valid() {
        let dir = repo_palettes();
        let mut count = 0;
        for entry in fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().is_some_and(|e| e == "toml") {
                Palette::from_file(&path).unwrap_or_else(|e| panic!("{e}"));
                count += 1;
            }
        }
        assert!(count >= 2, "cần ít nhất 2 palette, có {count}");
    }

    #[test]
    fn color_parsing() {
        assert_eq!(Color::parse("#74B8FC").unwrap().hex(), "74b8fc");
        assert!(Color::parse("74b8fc").is_err());
        assert!(Color::parse("#74b8f").is_err());
        assert!(Color::parse("#zzzzzz").is_err());
    }

    #[test]
    fn load_rejects_path_tricks() {
        let paths = Paths {
            datadir: repo_palettes().join(".."),
            config_dir: "/nonexistent".into(),
            state_dir: "/nonexistent".into(),
            data_home: "/nonexistent".into(),
            runtime_dir: "/nonexistent".into(),
            home: "/nonexistent".into(),
        };
        // datadir/palettes = theme/palettes trong repo
        assert!(Palette::load(&paths, "sky").is_ok());
        assert!(matches!(Palette::load(&paths, "../sky"), Err(PaletteError::BadName(_))));
        assert!(matches!(
            Palette::load(&paths, "khong-co"),
            Err(PaletteError::NotFound(_))
        ));
        assert!(list(&paths).contains(&"twilight".to_string()));
    }
}
