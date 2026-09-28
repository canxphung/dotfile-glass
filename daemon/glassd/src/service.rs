//! Trạng thái trung tâm của glassd: settings hiện tại, palette, và việc
//! đổi settings → ghi file → render state → áp ra hệ thống → báo sự kiện.
//!
//! D-Bus, socket và bộ theo dõi file đều gọi vào đây, nên mọi đường đổi
//! settings đi qua cùng một chỗ.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::Path;

use glass_core::Paths;
use glass_core::fsutil;
use glass_core::palette::{self, Palette};
use glass_core::render::{Context, Renderer};
use glass_core::settings::{self, Scalar, Settings, SettingsDoc};
use tokio::sync::{Mutex, broadcast};
use tracing::{debug, error, info, warn};

use crate::apply::{self, Actions};

#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum Event {
    /// Một khoá đổi giá trị (qua D-Bus, socket hay sửa file).
    Changed { key: String, value: Scalar },
    /// settings.toml vừa sửa tay bị lỗi; glassd giữ nguyên settings cũ.
    FileError { message: String },
}

#[derive(Debug, thiserror::Error)]
pub enum ServiceError {
    #[error(transparent)]
    Settings(#[from] settings::SettingsError),
    #[error(transparent)]
    Palette(#[from] palette::PaletteError),
    #[error("{0}")]
    Rejected(String),
    #[error("không ghi được settings.toml: {0}")]
    Io(#[from] io::Error),
}

struct Inner {
    doc: SettingsDoc,
    palette: Palette,
    /// Nội dung settings.toml lần cuối glassd đọc hoặc ghi, để bỏ qua sự
    /// kiện file do chính glassd gây ra.
    last_text: Option<String>,
    /// Lỗi của settings.toml hiện trên đĩa, nếu có. Khi có lỗi, glassd
    /// không ghi đè file để không làm mất phần người dùng đang sửa dở.
    file_error: Option<String>,
}

pub struct Service {
    paths: Paths,
    renderer: Renderer,
    inner: Mutex<Inner>,
    events: broadcast::Sender<Event>,
}

/// Palette mặc định, luôn có trong gói.
const FALLBACK_PALETTE: &str = "sky";

impl Service {
    /// Đọc settings.toml (tạo từ bản mẫu nếu chưa có) và palette.
    pub fn load(paths: Paths) -> anyhow::Result<Self> {
        let renderer = Renderer::new(paths.templates_dir());
        let file = paths.settings_file();

        if !file.exists() {
            let template =
                fs::read_to_string(paths.settings_template()).unwrap_or_else(|_| SettingsDoc::default_doc().text());
            fsutil::write_atomic(&file, &template)?;
            info!("tạo {} từ bản mẫu", file.display());
        }

        let (doc, last_text, file_error) = match read_settings(&file) {
            Ok((doc, text)) => (doc, Some(text), None),
            Err(message) => {
                error!("{message}; dùng settings mặc định cho tới khi file được sửa");
                (SettingsDoc::default_doc(), None, Some(message))
            }
        };

        let palette = load_palette_or_fallback(&paths, &doc.settings().appearance.palette)?;
        let (events, _) = broadcast::channel(64);

        Ok(Self {
            paths,
            renderer,
            inner: Mutex::new(Inner {
                doc,
                palette,
                last_text,
                file_error,
            }),
            events,
        })
    }

    pub fn paths(&self) -> &Paths {
        &self.paths
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.events.subscribe()
    }

    pub async fn get_all(&self) -> BTreeMap<String, Scalar> {
        settings::flatten(self.inner.lock().await.doc.settings())
    }

    pub async fn get(&self, key: &str) -> Result<Scalar, ServiceError> {
        Ok(self.inner.lock().await.doc.get(key)?)
    }

    pub fn palettes(&self) -> Vec<String> {
        palette::list(&self.paths)
    }

    /// Render và áp mọi thứ lúc khởi động. File state chưa đổi thì các
    /// dịch vụ liên quan không bị động tới.
    pub async fn startup(&self) {
        let actions = {
            let inner = self.inner.lock().await;
            let mut actions = self.render(&inner);
            actions.all_gsettings = true;
            actions.night_light = Some(inner.doc.settings().night_light.enabled);
            actions
        };
        apply::run(&actions).await;
    }

    pub async fn set(&self, key: &str, value: Scalar) -> Result<(), ServiceError> {
        let inner = self.inner.lock().await;
        let new_doc = inner.doc.set(key, value)?;
        self.check_new(&new_doc)?;
        self.commit(inner, new_doc).await
    }

    pub async fn reset(&self, key: &str) -> Result<(), ServiceError> {
        let inner = self.inner.lock().await;
        let new_doc = inner.doc.reset(key)?;
        self.check_new(&new_doc)?;
        self.commit(inner, new_doc).await
    }

    /// Đọc lại settings.toml sau khi người dùng sửa tay.
    pub async fn reload_from_disk(&self) -> Result<(), ServiceError> {
        let file = self.paths.settings_file();
        let text = match fs::read_to_string(&file) {
            Ok(text) => text,
            // Trình soạn thảo đôi khi xoá rồi mới ghi; lần sự kiện sau sẽ đọc được.
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
            Err(e) => return Err(e.into()),
        };

        let mut inner = self.inner.lock().await;
        if inner.last_text.as_deref() == Some(text.as_str()) {
            return Ok(());
        }

        let parsed = SettingsDoc::parse(&text)
            .map_err(ServiceError::from)
            .and_then(|doc| self.check_new(&doc).map(|()| doc));
        match parsed {
            Ok(doc) => {
                inner.last_text = Some(text);
                if inner.file_error.take().is_some() {
                    info!("settings.toml đã hợp lệ trở lại");
                }
                self.swap_and_apply(inner, doc).await;
                Ok(())
            }
            Err(e) => {
                let message = format!("settings.toml lỗi: {e}");
                warn!("{message}; giữ settings cũ");
                inner.last_text = Some(text);
                inner.file_error = Some(message.clone());
                drop(inner);
                let _ = self.events.send(Event::FileError { message });
                Err(e)
            }
        }
    }

    /// Kiểm tra những gì cần hệ thống thật (palette có tồn tại, file hình
    /// nền có thật) mà glass-core không tự biết.
    fn check_new(&self, doc: &SettingsDoc) -> Result<(), ServiceError> {
        let s = doc.settings();
        Palette::load(&self.paths, &s.appearance.palette)?;
        let wallpaper = s.wallpaper.path.trim();
        if !wallpaper.is_empty() && !self.paths.expand_home(wallpaper).is_file() {
            return Err(ServiceError::Rejected(format!(
                "không thấy file hình nền {wallpaper:?}"
            )));
        }
        Ok(())
    }

    /// Ghi settings.toml rồi áp thay đổi.
    async fn commit(
        &self,
        mut inner: tokio::sync::MutexGuard<'_, Inner>,
        doc: SettingsDoc,
    ) -> Result<(), ServiceError> {
        if let Some(problem) = &inner.file_error {
            return Err(ServiceError::Rejected(format!(
                "{problem}. Sửa file trước rồi thử lại."
            )));
        }
        let text = doc.text();
        fsutil::write_atomic(&self.paths.settings_file(), &text)?;
        inner.last_text = Some(text);
        self.swap_and_apply(inner, doc).await;
        Ok(())
    }

    async fn swap_and_apply(&self, mut inner: tokio::sync::MutexGuard<'_, Inner>, doc: SettingsDoc) {
        let changed = settings::changed_keys(inner.doc.settings(), doc.settings());
        if changed.is_empty() {
            return;
        }

        let old_palette = inner.doc.settings().appearance.palette.clone();
        inner.doc = doc;
        let new_palette = inner.doc.settings().appearance.palette.clone();
        if new_palette != old_palette {
            match Palette::load(&self.paths, &new_palette) {
                Ok(p) => inner.palette = p,
                Err(e) => warn!("{e}; giữ palette {old_palette:?}"),
            }
        }

        let mut actions = self.render(&inner);
        for (key, _) in &changed {
            actions.note_key(key);
        }
        drop(inner);

        apply::run(&actions).await;
        for (key, value) in changed {
            info!("{key} = {value}");
            let _ = self.events.send(Event::Changed { key, value });
        }
    }

    /// Render file state và cho biết cần báo những ai.
    fn render(&self, inner: &Inner) -> Actions {
        let settings = effective_settings(&self.paths, inner.doc.settings());
        let ctx = Context::new(&self.paths, &settings, &inner.palette);
        let mut actions = Actions::new(&self.paths, &settings);

        let outputs = match self.renderer.render(&ctx) {
            Ok(outputs) => outputs,
            Err(e) => {
                error!("không render được file theme: {e}");
                return actions;
            }
        };
        for out in outputs {
            let path = self.paths.state_dir.join(out.path);
            match fsutil::write_if_changed(&path, &out.content) {
                Ok(true) => {
                    debug!("ghi {}", path.display());
                    actions.note_file(out.path);
                }
                Ok(false) => {}
                Err(e) => error!("không ghi được {}: {e}", path.display()),
            }
        }
        actions
    }
}

fn read_settings(file: &Path) -> Result<(SettingsDoc, String), String> {
    let text = fs::read_to_string(file).map_err(|e| format!("không đọc được {}: {e}", file.display()))?;
    let doc = SettingsDoc::parse(&text).map_err(|e| e.to_string())?;
    Ok((doc, text))
}

fn load_palette_or_fallback(paths: &Paths, name: &str) -> anyhow::Result<Palette> {
    match Palette::load(paths, name) {
        Ok(p) => Ok(p),
        Err(e) => {
            warn!("{e}; dùng palette {FALLBACK_PALETTE:?}");
            Ok(Palette::load(paths, FALLBACK_PALETTE)?)
        }
    }
}

/// Settings dùng để render: hình nền không còn tồn tại thì về hình mặc
/// định, để hyprpaper không bị trống màn hình.
fn effective_settings(paths: &Paths, settings: &Settings) -> Settings {
    let mut s = settings.clone();
    let wallpaper = s.wallpaper.path.trim();
    if !wallpaper.is_empty() && !paths.expand_home(wallpaper).is_file() {
        warn!("không thấy hình nền {wallpaper:?}, dùng hình mặc định");
        s.wallpaper.path.clear();
    }
    s
}
