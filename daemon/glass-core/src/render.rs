//! Render các file glassd ghi vào thư mục state (`~/.local/state/glass`).
//!
//! Template nằm trong `<datadir>/templates` (repo: `theme/runtime/`), viết
//! bằng cú pháp Jinja. File mặc định của gói (`hyprlock.conf`, `glass.conf`
//! của kitty...) nạp các file này bằng `source`/`include`.

use std::path::Path;

use minijinja::{Environment, Error, ErrorKind, UndefinedBehavior};
use serde::Serialize;

use crate::palette::{Color, Palette};
use crate::paths::Paths;
use crate::settings::Settings;

pub const THEME_HYPRLAND: &str = "theme/hyprland.lua";
pub const THEME_HYPRLOCK: &str = "theme/hyprlock.conf";
pub const THEME_KITTY: &str = "theme/kitty.conf";
pub const THEME_SHELL: &str = "theme/shell.json";
pub const IDLE: &str = "idle.conf";
pub const WALLPAPER: &str = "wallpaper.conf";
pub const NIGHT_LIGHT: &str = "nightlight.conf";

/// (file đích trong thư mục state, template)
const TEMPLATES: &[(&str, &str)] = &[
    (THEME_HYPRLAND, "hyprland.lua.j2"),
    (THEME_HYPRLOCK, "hyprlock.conf.j2"),
    (THEME_KITTY, "kitty.conf.j2"),
    (IDLE, "idle.conf.j2"),
    (WALLPAPER, "wallpaper.conf.j2"),
    (NIGHT_LIGHT, "nightlight.conf.j2"),
];

/// Một file đã render; `path` tính từ thư mục state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Output {
    pub path: &'static str,
    pub content: String,
}

#[derive(Debug, thiserror::Error)]
#[error("template {name}: {source:#}")]
pub struct RenderError {
    pub name: String,
    #[source]
    pub source: Error,
}

/// Dữ liệu đưa vào template.
#[derive(Debug, Serialize)]
pub struct Context<'a> {
    pub palette: &'a Palette,
    pub settings: &'a Settings,
    /// Đường dẫn hình nền tuyệt đối (đã xử lý chuỗi rỗng và "~/").
    pub wallpaper: String,
    pub font_family: String,
    pub monospace_family: String,
    pub monospace_size: String,
}

/// Tách "Noto Sans 10" thành ("Noto Sans", Some("10")).
pub fn split_font(desc: &str) -> (String, Option<String>) {
    let desc = desc.trim();
    match desc.rsplit_once(char::is_whitespace) {
        Some((family, size)) if size.parse::<f32>().is_ok_and(|s| s > 0.0) => {
            (family.trim_end().to_string(), Some(size.to_string()))
        }
        _ => (desc.to_string(), None),
    }
}

impl<'a> Context<'a> {
    pub fn new(paths: &Paths, settings: &'a Settings, palette: &'a Palette) -> Self {
        let wallpaper = if settings.wallpaper.path.trim().is_empty() {
            paths.default_wallpaper()
        } else {
            paths.expand_home(settings.wallpaper.path.trim())
        };
        let (font_family, _) = split_font(&settings.appearance.font);
        let (monospace_family, monospace_size) = split_font(&settings.appearance.monospace_font);
        Self {
            palette,
            settings,
            wallpaper: wallpaper.to_string_lossy().into_owned(),
            font_family,
            monospace_family,
            monospace_size: monospace_size.unwrap_or_else(|| "11".into()),
        }
    }
}

fn color_arg(value: &str) -> Result<Color, Error> {
    Color::parse(value).map_err(|e| Error::new(ErrorKind::InvalidOperation, e))
}

/// `"#74b8fc" | hex` → `74b8fc`
fn hex_filter(value: String) -> Result<String, Error> {
    Ok(color_arg(&value)?.hex().to_string())
}

/// `"#74b8fc" | rgba("cc")` → `rgba(74b8fccc)`, dạng màu của Hyprland.
fn rgba_filter(value: String, alpha: String) -> Result<String, Error> {
    let color = color_arg(&value)?;
    if alpha.len() != 2 || !alpha.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(Error::new(
            ErrorKind::InvalidOperation,
            format!("alpha {alpha:?} phải là 2 chữ số hex"),
        ));
    }
    Ok(format!("rgba({}{})", color.hex(), alpha.to_ascii_lowercase()))
}

/// Trong file hyprlang, `#` mở đầu comment; viết `##` để giữ ký tự #.
fn hyprlang_filter(value: String) -> String {
    value.replace('#', "##")
}

#[derive(Serialize)]
struct ShellTheme<'a> {
    palette: &'a Palette,
    color_scheme: crate::settings::ColorScheme,
    font_family: &'a str,
    monospace_family: &'a str,
}

pub struct Renderer {
    env: Environment<'static>,
}

impl Renderer {
    pub fn new(templates_dir: impl AsRef<Path>) -> Self {
        let mut env = Environment::new();
        env.set_loader(minijinja::path_loader(templates_dir.as_ref()));
        env.set_undefined_behavior(UndefinedBehavior::Strict);
        env.set_keep_trailing_newline(true);
        env.set_trim_blocks(true);
        env.set_lstrip_blocks(true);
        env.add_filter("hex", hex_filter);
        env.add_filter("rgba", rgba_filter);
        env.add_filter("hyprlang", hyprlang_filter);
        Self { env }
    }

    pub fn render(&self, ctx: &Context<'_>) -> Result<Vec<Output>, RenderError> {
        let mut outputs = Vec::with_capacity(TEMPLATES.len() + 1);
        for (path, name) in TEMPLATES {
            let content = self
                .env
                .get_template(name)
                .and_then(|t| t.render(ctx))
                .map_err(|source| RenderError {
                    name: (*name).into(),
                    source,
                })?;
            outputs.push(Output { path, content });
        }

        let shell = ShellTheme {
            palette: ctx.palette,
            color_scheme: ctx.settings.appearance.color_scheme,
            font_family: &ctx.font_family,
            monospace_family: &ctx.monospace_family,
        };
        let mut json = serde_json::to_string_pretty(&shell).expect("theme luôn chuyển được sang JSON");
        json.push('\n');
        outputs.push(Output {
            path: THEME_SHELL,
            content: json,
        });
        Ok(outputs)
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;

    use super::*;
    use crate::settings::{Scalar, SettingsDoc};

    fn repo() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
    }

    /// Paths giả với datadir là placeholder, giống file state khởi tạo
    /// trong repo (Makefile thay placeholder lúc cài).
    fn paths() -> Paths {
        Paths {
            datadir: "@GLASS_DATADIR@".into(),
            config_dir: "/home/u/.config/glass".into(),
            state_dir: "/home/u/.local/state/glass".into(),
            data_home: "/nonexistent".into(),
            runtime_dir: "/nonexistent".into(),
            home: "/home/u".into(),
        }
    }

    fn palette(name: &str) -> Palette {
        Palette::from_file(&repo().join(format!("theme/palettes/{name}.toml"))).unwrap()
    }

    fn render(settings: &Settings, palette: &Palette) -> Vec<Output> {
        let renderer = Renderer::new(repo().join("theme/runtime"));
        renderer
            .render(&Context::new(&paths(), settings, palette))
            .unwrap_or_else(|e| panic!("{e}"))
    }

    fn find<'a>(outputs: &'a [Output], path: &str) -> &'a str {
        &outputs.iter().find(|o| o.path == path).unwrap().content
    }

    /// File state khởi tạo trong defaults/state phải đúng bằng những gì
    /// glassd render với settings mặc định. Chạy với GLASS_UPDATE_STATE=1
    /// để ghi lại các file đó sau khi sửa template.
    #[test]
    fn bootstrap_state_matches_render() {
        let outputs = render(&Settings::default(), &palette("sky"));
        let dir = repo().join("defaults/state");
        let update = std::env::var_os("GLASS_UPDATE_STATE").is_some();
        for out in &outputs {
            let file = dir.join(out.path);
            if update {
                crate::fsutil::write_if_changed(&file, &out.content).unwrap();
                continue;
            }
            let expected = fs::read_to_string(&file).unwrap_or_else(|e| panic!("{}: {e}", file.display()));
            assert_eq!(
                expected, out.content,
                "{} lệch với template; chạy GLASS_UPDATE_STATE=1 cargo test",
                out.path
            );
        }
    }

    #[test]
    fn palettes_change_theme_files() {
        let sky = render(&Settings::default(), &palette("sky"));
        let twilight = render(&Settings::default(), &palette("twilight"));
        for path in [THEME_HYPRLAND, THEME_HYPRLOCK, THEME_KITTY, THEME_SHELL] {
            assert_ne!(find(&sky, path), find(&twilight, path), "{path}");
        }
        assert!(find(&twilight, THEME_HYPRLAND).contains("rgba(8b78e6bb)"));
        assert_eq!(find(&sky, IDLE), find(&twilight, IDLE));
    }

    #[test]
    fn idle_skips_disabled_steps() {
        let doc = SettingsDoc::default_doc()
            .set("idle.dim", Scalar::Int(0))
            .unwrap()
            .set("idle.suspend", Scalar::Int(0))
            .unwrap();
        let idle = render(doc.settings(), &palette("sky"));
        let idle = find(&idle, IDLE);
        assert_eq!(idle.matches("listener {").count(), 2, "{idle}");
        assert!(!idle.contains("systemctl suspend"));
        assert!(idle.contains("timeout = 300"));
    }

    #[test]
    fn wallpaper_and_fonts() {
        let doc = SettingsDoc::default_doc()
            .set("wallpaper.path", Scalar::Str("~/Ảnh/#1.jpg".into()))
            .unwrap()
            .set("appearance.monospace_font", Scalar::Str("Fira Code 13.5".into()))
            .unwrap();
        let out = render(doc.settings(), &palette("sky"));
        assert!(find(&out, WALLPAPER).contains("path = /home/u/Ảnh/##1.jpg"));
        let kitty = find(&out, THEME_KITTY);
        assert!(kitty.contains("font_family      Fira Code\n"), "{kitty}");
        assert!(kitty.contains("font_size        13.5\n"), "{kitty}");
    }

    #[test]
    fn night_light_profiles() {
        let doc = SettingsDoc::default_doc()
            .set("night_light.temperature", Scalar::Int(3800))
            .unwrap();
        let out = render(doc.settings(), &palette("sky"));
        let conf = find(&out, NIGHT_LIGHT);
        assert!(conf.contains("time = 20:00\n    temperature = 3800"), "{conf}");
        assert!(conf.contains("time = 06:30\n    identity = true"), "{conf}");
    }

    #[test]
    fn shell_json_is_valid() {
        let out = render(&Settings::default(), &palette("sky"));
        let json: serde_json::Value = serde_json::from_str(find(&out, THEME_SHELL)).unwrap();
        assert_eq!(json["palette"]["glass"]["tint"], "#74b8fc");
        assert_eq!(json["color_scheme"], "dark");
    }

    #[test]
    fn split_font_description() {
        assert_eq!(split_font("Noto Sans 10"), ("Noto Sans".into(), Some("10".into())));
        assert_eq!(split_font("Noto Sans"), ("Noto Sans".into(), None));
        assert_eq!(
            split_font(" Inter Bold 11.5 "),
            ("Inter Bold".into(), Some("11.5".into()))
        );
    }

    #[test]
    fn filters_reject_bad_colors() {
        assert!(rgba_filter("#12345".into(), "ff".into()).is_err());
        assert!(rgba_filter("#123456".into(), "f".into()).is_err());
        assert_eq!(rgba_filter("#ABCDEF".into(), "CC".into()).unwrap(), "rgba(abcdefcc)");
    }
}
