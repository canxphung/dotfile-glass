//! Phần dùng chung của Glass: đường dẫn, settings, palette và render các
//! file theme/state mà glassd ghi ra `~/.local/state/glass`.

pub mod fsutil;
pub mod palette;
pub mod paths;
pub mod render;
pub mod settings;

pub use palette::{Palette, PaletteError};
pub use paths::Paths;
pub use render::{Output, RenderError, Renderer};
pub use settings::{Scalar, Settings, SettingsDoc, SettingsError};

/// Tên D-Bus của glassd.
pub const DBUS_NAME: &str = "io.github.canxphung.Glass1";
/// Đường dẫn object D-Bus của glassd.
pub const DBUS_PATH: &str = "/io/github/canxphung/Glass1";
/// Interface D-Bus quản lý settings.
pub const DBUS_INTERFACE: &str = "io.github.canxphung.Glass1.Settings";
