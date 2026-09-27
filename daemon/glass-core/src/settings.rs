//! `settings.toml`: mô hình, kiểm tra hợp lệ, đọc và ghi theo từng khoá.
//!
//! Ghi qua `toml_edit` nên comment và thứ tự dòng người dùng viết được giữ
//! nguyên; chỉ giá trị của khoá được đổi là thay.

use std::collections::BTreeMap;
use std::fmt;

use serde::{Deserialize, Serialize};
use toml_edit::{DocumentMut, Item, Table};

/// Phiên bản cấu trúc settings.toml mà bản glassd này hiểu.
pub const SCHEMA_VERSION: i64 = 1;

/// Giới hạn thời gian chờ khi rảnh: 1 ngày.
pub const MAX_IDLE_SECONDS: u32 = 86_400;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct Settings {
    pub version: i64,
    pub appearance: Appearance,
    pub wallpaper: Wallpaper,
    pub idle: Idle,
    pub night_light: NightLight,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            version: SCHEMA_VERSION,
            appearance: Appearance::default(),
            wallpaper: Wallpaper::default(),
            idle: Idle::default(),
            night_light: NightLight::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct Appearance {
    pub palette: String,
    pub color_scheme: ColorScheme,
    pub font: String,
    pub monospace_font: String,
}

impl Default for Appearance {
    fn default() -> Self {
        Self {
            palette: "sky".into(),
            color_scheme: ColorScheme::Dark,
            font: "Noto Sans 10".into(),
            monospace_font: "JetBrainsMono Nerd Font 11".into(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ColorScheme {
    Dark,
    Light,
    Default,
}

impl ColorScheme {
    /// Giá trị cho `org.gnome.desktop.interface color-scheme`.
    pub fn gsettings_value(self) -> &'static str {
        match self {
            Self::Dark => "prefer-dark",
            Self::Light => "prefer-light",
            Self::Default => "default",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct Wallpaper {
    /// Đường dẫn hình; chuỗi rỗng là hình mặc định của Glass.
    pub path: String,
    pub fit: Fit,
}

impl Default for Wallpaper {
    fn default() -> Self {
        Self {
            path: String::new(),
            fit: Fit::Cover,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Fit {
    Cover,
    Contain,
    Tile,
    Fill,
}

/// Thời gian rảnh (giây) trước mỗi bước; 0 là bỏ bước đó.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct Idle {
    pub dim: u32,
    pub lock: u32,
    pub screen_off: u32,
    pub suspend: u32,
}

impl Default for Idle {
    fn default() -> Self {
        Self {
            dim: 150,
            lock: 300,
            screen_off: 330,
            suspend: 1800,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct NightLight {
    pub enabled: bool,
    /// Nhiệt độ màu (K) khi bật; thấp hơn là ấm hơn.
    pub temperature: u32,
    /// Giờ bắt đầu, dạng HH:MM.
    pub start: String,
    /// Giờ kết thúc, dạng HH:MM.
    pub end: String,
}

impl Default for NightLight {
    fn default() -> Self {
        Self {
            enabled: false,
            temperature: 4500,
            start: "20:00".into(),
            end: "06:30".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum SettingsError {
    #[error("settings.toml không đọc được: {0}")]
    Parse(String),
    #[error("không có khoá {0}")]
    UnknownKey(String),
    #[error("khoá {0} chỉ đọc")]
    ReadOnly(String),
    #[error("{key} cần kiểu {expected}, nhận {got}")]
    Type {
        key: String,
        expected: &'static str,
        got: &'static str,
    },
    #[error("{key}: {reason}")]
    Invalid { key: String, reason: String },
    #[error("settings.toml có version {0}, mới hơn mức glassd này hỗ trợ ({SCHEMA_VERSION})")]
    NewerVersion(i64),
}

fn invalid(key: &str, reason: impl Into<String>) -> SettingsError {
    SettingsError::Invalid {
        key: key.into(),
        reason: reason.into(),
    }
}

/// Tên palette hợp lệ: chữ thường, số, `-`, `_`. Chặn luôn đường dẫn.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 64
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
}

/// Đọc giờ dạng `H:MM` hoặc `HH:MM`.
pub fn parse_hhmm(text: &str) -> Option<(u8, u8)> {
    let (h, m) = text.split_once(':')?;
    if h.is_empty() || h.len() > 2 || m.len() != 2 {
        return None;
    }
    let h: u8 = h.parse().ok()?;
    let m: u8 = m.parse().ok()?;
    (h < 24 && m < 60).then_some((h, m))
}

impl Settings {
    pub fn validate(&self) -> Result<(), SettingsError> {
        if self.version > SCHEMA_VERSION {
            return Err(SettingsError::NewerVersion(self.version));
        }
        if self.version < 1 {
            return Err(invalid("version", "phải từ 1 trở lên"));
        }

        let a = &self.appearance;
        if !valid_name(&a.palette) {
            return Err(invalid(
                "appearance.palette",
                "tên palette chỉ gồm chữ thường, số, - và _",
            ));
        }
        if a.font.trim().is_empty() {
            return Err(invalid("appearance.font", "không được để trống"));
        }
        if a.monospace_font.trim().is_empty() {
            return Err(invalid("appearance.monospace_font", "không được để trống"));
        }

        for (key, value) in [
            ("idle.dim", self.idle.dim),
            ("idle.lock", self.idle.lock),
            ("idle.screen_off", self.idle.screen_off),
            ("idle.suspend", self.idle.suspend),
        ] {
            if value > MAX_IDLE_SECONDS {
                return Err(invalid(key, format!("tối đa {MAX_IDLE_SECONDS} giây")));
            }
        }

        let n = &self.night_light;
        if !(1000..=6500).contains(&n.temperature) {
            return Err(invalid("night_light.temperature", "phải trong khoảng 1000..6500"));
        }
        let start = parse_hhmm(&n.start).ok_or_else(|| invalid("night_light.start", "cần dạng HH:MM"))?;
        let end = parse_hhmm(&n.end).ok_or_else(|| invalid("night_light.end", "cần dạng HH:MM"))?;
        if start == end {
            return Err(invalid("night_light.end", "phải khác giờ bắt đầu"));
        }
        Ok(())
    }
}

/// Giá trị đơn của một khoá. Settings của Glass chỉ có giá trị đơn.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Scalar {
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
}

impl Scalar {
    pub fn type_name(&self) -> &'static str {
        match self {
            Self::Bool(_) => "bool",
            Self::Int(_) => "số nguyên",
            Self::Float(_) => "số thực",
            Self::Str(_) => "chuỗi",
        }
    }

    fn from_json(value: &serde_json::Value) -> Option<Self> {
        match value {
            serde_json::Value::Bool(b) => Some(Self::Bool(*b)),
            serde_json::Value::Number(n) => n.as_i64().map(Self::Int).or_else(|| n.as_f64().map(Self::Float)),
            serde_json::Value::String(s) => Some(Self::Str(s.clone())),
            _ => None,
        }
    }

    fn to_toml(&self) -> toml_edit::Value {
        match self {
            Self::Bool(b) => (*b).into(),
            Self::Int(i) => (*i).into(),
            Self::Float(f) => (*f).into(),
            Self::Str(s) => s.as_str().into(),
        }
    }

    /// Đọc chuỗi người dùng gõ (vd. từ dòng lệnh) theo kiểu của `like`.
    pub fn parse_as(text: &str, like: &Scalar) -> Result<Scalar, String> {
        match like {
            Self::Bool(_) => match text {
                "true" | "on" | "yes" | "1" => Ok(Self::Bool(true)),
                "false" | "off" | "no" | "0" => Ok(Self::Bool(false)),
                _ => Err(format!("cần true/false, nhận {text:?}")),
            },
            Self::Int(_) => text
                .parse()
                .map(Self::Int)
                .map_err(|_| format!("cần số nguyên, nhận {text:?}")),
            Self::Float(_) => text
                .parse()
                .map(Self::Float)
                .map_err(|_| format!("cần số, nhận {text:?}")),
            Self::Str(_) => Ok(Self::Str(text.to_string())),
        }
    }

    /// Ép kiểu cho khớp giá trị mặc định (số nguyên dùng được cho khoá số thực).
    fn coerce(self, key: &str, expected: &Scalar) -> Result<Scalar, SettingsError> {
        match (expected, self) {
            (Self::Bool(_), v @ Self::Bool(_))
            | (Self::Int(_), v @ Self::Int(_))
            | (Self::Float(_), v @ Self::Float(_))
            | (Self::Str(_), v @ Self::Str(_)) => Ok(v),
            (Self::Float(_), Self::Int(i)) => Ok(Self::Float(i as f64)),
            (expected, got) => Err(SettingsError::Type {
                key: key.into(),
                expected: expected.type_name(),
                got: got.type_name(),
            }),
        }
    }
}

impl fmt::Display for Scalar {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Bool(b) => write!(f, "{b}"),
            Self::Int(i) => write!(f, "{i}"),
            Self::Float(x) => write!(f, "{x}"),
            Self::Str(s) => write!(f, "{s:?}"),
        }
    }
}

/// Trải settings thành các cặp `mục.khoá = giá trị`.
pub fn flatten(settings: &Settings) -> BTreeMap<String, Scalar> {
    fn walk(prefix: &str, value: &serde_json::Value, out: &mut BTreeMap<String, Scalar>) {
        match value {
            serde_json::Value::Object(map) => {
                for (k, v) in map {
                    let key = if prefix.is_empty() {
                        k.clone()
                    } else {
                        format!("{prefix}.{k}")
                    };
                    walk(&key, v, out);
                }
            }
            other => {
                if let Some(s) = Scalar::from_json(other) {
                    out.insert(prefix.to_string(), s);
                }
            }
        }
    }

    let json = serde_json::to_value(settings).expect("Settings luôn chuyển được sang JSON");
    let mut out = BTreeMap::new();
    walk("", &json, &mut out);
    out
}

/// Các khoá có giá trị khác nhau giữa hai bản settings, kèm giá trị mới.
pub fn changed_keys(old: &Settings, new: &Settings) -> Vec<(String, Scalar)> {
    let old = flatten(old);
    flatten(new)
        .into_iter()
        .filter(|(k, v)| old.get(k) != Some(v))
        .collect()
}

/// settings.toml đã đọc: giữ cả văn bản gốc (để ghi lại giữ comment) lẫn
/// giá trị đã kiểm tra.
#[derive(Debug, Clone)]
pub struct SettingsDoc {
    doc: DocumentMut,
    settings: Settings,
}

impl SettingsDoc {
    pub fn parse(text: &str) -> Result<Self, SettingsError> {
        let doc: DocumentMut = text
            .parse()
            .map_err(|e: toml_edit::TomlError| SettingsError::Parse(e.to_string()))?;
        let settings: Settings = toml::from_str(text).map_err(|e| SettingsError::Parse(e.to_string()))?;
        settings.validate()?;
        Ok(Self { doc, settings })
    }

    /// Bản mặc định không comment, dùng khi thiếu cả file mẫu.
    pub fn default_doc() -> Self {
        let text = toml::to_string(&Settings::default()).expect("Settings mặc định luôn ghi được");
        Self::parse(&text).expect("Settings mặc định luôn hợp lệ")
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    pub fn text(&self) -> String {
        self.doc.to_string()
    }

    pub fn get(&self, key: &str) -> Result<Scalar, SettingsError> {
        flatten(&self.settings)
            .remove(key)
            .ok_or_else(|| SettingsError::UnknownKey(key.into()))
    }

    /// Trả về bản mới đã đổi `key`; bản hiện tại không bị đụng tới.
    pub fn set(&self, key: &str, value: Scalar) -> Result<Self, SettingsError> {
        if key == "version" {
            return Err(SettingsError::ReadOnly(key.into()));
        }
        let defaults = flatten(&Settings::default());
        let expected = defaults.get(key).ok_or_else(|| SettingsError::UnknownKey(key.into()))?;
        let value = value.coerce(key, expected)?;
        let (section, field) = key
            .split_once('.')
            .ok_or_else(|| SettingsError::UnknownKey(key.into()))?;

        let mut doc = self.doc.clone();
        if doc.get(section).is_none() {
            doc.insert(section, Item::Table(Table::new()));
        }
        let table = doc[section]
            .as_table_like_mut()
            .ok_or_else(|| invalid(section, "phải là một mục [bảng]"))?;

        let mut new_value = value.to_toml();
        match table.get_mut(field) {
            Some(Item::Value(old)) => {
                // Giữ khoảng trắng và comment cuối dòng của giá trị cũ.
                *new_value.decor_mut() = old.decor().clone();
                *old = new_value;
            }
            _ => {
                table.insert(field, Item::Value(new_value));
            }
        }

        let text = doc.to_string();
        let settings: Settings = toml::from_str(&text).map_err(|e| invalid(key, e.to_string()))?;
        settings.validate()?;
        Ok(Self { doc, settings })
    }

    /// Đưa `key` về giá trị mặc định.
    pub fn reset(&self, key: &str) -> Result<Self, SettingsError> {
        let default = flatten(&Settings::default())
            .remove(key)
            .ok_or_else(|| SettingsError::UnknownKey(key.into()))?;
        self.set(key, default)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEMPLATE: &str = include_str!("../../../defaults/settings.toml");

    #[test]
    fn template_matches_defaults() {
        let doc = SettingsDoc::parse(TEMPLATE).expect("bản mẫu settings.toml phải hợp lệ");
        assert_eq!(doc.settings(), &Settings::default());
    }

    #[test]
    fn default_doc_roundtrips() {
        assert_eq!(SettingsDoc::default_doc().settings(), &Settings::default());
    }

    #[test]
    fn set_keeps_comments_and_other_lines() {
        let text = "# đầu file\nversion = 1\n\n[appearance]\n# chọn palette\npalette = \"sky\"   # ghi chú cuối dòng\nfont = \"Noto Sans 10\"\n";
        let doc = SettingsDoc::parse(text).unwrap();
        let doc = doc.set("appearance.palette", Scalar::Str("twilight".into())).unwrap();
        let out = doc.text();
        assert!(out.contains("# đầu file"));
        assert!(out.contains("# chọn palette"));
        assert!(out.contains("palette = \"twilight\"   # ghi chú cuối dòng"), "{out}");
        assert!(out.contains("font = \"Noto Sans 10\""));
        assert_eq!(doc.settings().appearance.palette, "twilight");
    }

    #[test]
    fn set_creates_missing_section() {
        let doc = SettingsDoc::parse("version = 1\n").unwrap();
        let doc = doc.set("idle.lock", Scalar::Int(600)).unwrap();
        assert_eq!(doc.settings().idle.lock, 600);
        assert!(doc.text().contains("[idle]"));
    }

    #[test]
    fn set_rejects_bad_input() {
        let doc = SettingsDoc::default_doc();
        assert!(matches!(
            doc.set("nope.key", Scalar::Int(1)),
            Err(SettingsError::UnknownKey(_))
        ));
        assert!(matches!(
            doc.set("version", Scalar::Int(2)),
            Err(SettingsError::ReadOnly(_))
        ));
        assert!(matches!(
            doc.set("idle.lock", Scalar::Str("x".into())),
            Err(SettingsError::Type { .. })
        ));
        assert!(matches!(
            doc.set("appearance.color_scheme", Scalar::Str("tím".into())),
            Err(SettingsError::Invalid { .. })
        ));
        assert!(matches!(
            doc.set("night_light.start", Scalar::Str("25:00".into())),
            Err(SettingsError::Invalid { .. })
        ));
        assert!(matches!(
            doc.set("appearance.palette", Scalar::Str("../x".into())),
            Err(SettingsError::Invalid { .. })
        ));
        assert!(matches!(
            doc.set("idle.lock", Scalar::Int(-1)),
            Err(SettingsError::Invalid { .. })
        ));
    }

    #[test]
    fn reset_restores_default() {
        let doc = SettingsDoc::default_doc().set("idle.dim", Scalar::Int(30)).unwrap();
        assert_eq!(doc.reset("idle.dim").unwrap().settings().idle.dim, 150);
    }

    #[test]
    fn parse_rejects_unknown_and_newer() {
        assert!(matches!(
            SettingsDoc::parse("[appearance]\npalete = \"sky\"\n"),
            Err(SettingsError::Parse(_))
        ));
        assert!(matches!(
            SettingsDoc::parse("version = 99\n"),
            Err(SettingsError::NewerVersion(99))
        ));
    }

    #[test]
    fn missing_sections_use_defaults() {
        let doc = SettingsDoc::parse("[idle]\nlock = 60\n").unwrap();
        assert_eq!(doc.settings().idle.lock, 60);
        assert_eq!(doc.settings().appearance, Appearance::default());
    }

    #[test]
    fn changed_keys_lists_only_differences() {
        let a = Settings::default();
        let mut b = a.clone();
        b.idle.dim = 10;
        b.appearance.color_scheme = ColorScheme::Light;
        let changed = changed_keys(&a, &b);
        assert_eq!(
            changed,
            vec![
                ("appearance.color_scheme".to_string(), Scalar::Str("light".into())),
                ("idle.dim".to_string(), Scalar::Int(10)),
            ]
        );
    }

    #[test]
    fn parses_cli_values() {
        assert_eq!(Scalar::parse_as("on", &Scalar::Bool(false)), Ok(Scalar::Bool(true)));
        assert_eq!(Scalar::parse_as("42", &Scalar::Int(0)), Ok(Scalar::Int(42)));
        assert!(Scalar::parse_as("abc", &Scalar::Int(0)).is_err());
        assert_eq!(
            Scalar::parse_as("sky", &Scalar::Str(String::new())),
            Ok(Scalar::Str("sky".into()))
        );
    }

    #[test]
    fn hhmm() {
        assert_eq!(parse_hhmm("6:30"), Some((6, 30)));
        assert_eq!(parse_hhmm("20:00"), Some((20, 0)));
        assert_eq!(parse_hhmm("24:00"), None);
        assert_eq!(parse_hhmm("7:5"), None);
    }
}
