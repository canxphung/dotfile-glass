//! glassctl: đọc và đổi settings của Glass qua D-Bus (glassd).

use std::collections::{BTreeMap, HashMap};
use std::process::ExitCode;

use anyhow::{Context, anyhow, bail};
use clap::{Parser, Subcommand};
use glass_core::settings::Scalar;
use glass_core::{DBUS_INTERFACE, DBUS_NAME, DBUS_PATH};
use zbus::blocking::Connection;
use zbus::proxy;
use zbus::zvariant::{OwnedValue, Value};

#[proxy(
    interface = "io.github.canxphung.Glass1.Settings",
    default_service = "io.github.canxphung.Glass1",
    default_path = "/io/github/canxphung/Glass1"
)]
trait Settings {
    fn get(&self, key: &str) -> zbus::Result<OwnedValue>;
    fn get_all(&self) -> zbus::Result<HashMap<String, OwnedValue>>;
    fn set(&self, key: &str, value: &Value<'_>) -> zbus::Result<()>;
    fn reset(&self, key: &str) -> zbus::Result<()>;
    fn list_palettes(&self) -> zbus::Result<Vec<String>>;
    fn reload(&self) -> zbus::Result<()>;

    #[zbus(property)]
    fn version(&self) -> zbus::Result<String>;

    #[zbus(signal)]
    fn changed(&self, key: &str, value: Value<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    fn file_error(&self, message: &str) -> zbus::Result<()>;
}

#[derive(Parser)]
#[command(name = "glassctl", version, about = "Đọc và đổi settings của Glass (qua glassd)")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// In giá trị một khoá, hoặc mọi khoá nếu bỏ trống.
    Get { key: Option<String> },
    /// Đổi một khoá, vd. `glassctl set idle.lock 600`.
    Set { key: String, value: String },
    /// Đưa một khoá về mặc định.
    Reset { key: String },
    /// Liệt kê palette; dấu * là palette đang dùng.
    Palettes,
    /// Đổi palette, vd. `glassctl palette twilight`.
    Palette { name: String },
    /// Đổi hình nền; `default` để về hình mặc định.
    Wallpaper { path: String },
    /// Đọc lại settings.toml ngay.
    Reload,
    /// In các thay đổi settings khi chúng xảy ra (Ctrl+C để dừng).
    Watch,
}

fn scalar(value: &Value<'_>) -> anyhow::Result<Scalar> {
    Ok(match value {
        Value::Bool(b) => Scalar::Bool(*b),
        Value::I64(i) => Scalar::Int(*i),
        Value::I32(i) => Scalar::Int((*i).into()),
        Value::U32(i) => Scalar::Int((*i).into()),
        Value::F64(f) => Scalar::Float(*f),
        Value::Str(s) => Scalar::Str(s.to_string()),
        Value::Value(inner) => scalar(inner)?,
        other => bail!("glassd trả về kiểu lạ: {}", other.value_signature()),
    })
}

fn to_value(s: &Scalar) -> Value<'static> {
    match s {
        Scalar::Bool(b) => Value::from(*b),
        Scalar::Int(i) => Value::from(*i),
        Scalar::Float(f) => Value::from(*f),
        Scalar::Str(s) => Value::from(s.clone()),
    }
}

/// Giá trị để in cho script dùng: chuỗi không có ngoặc kép.
fn plain(s: &Scalar) -> String {
    match s {
        Scalar::Str(s) => s.clone(),
        other => other.to_string(),
    }
}

/// Lỗi D-Bus dễ hiểu hơn cho người dùng.
fn explain(e: zbus::Error) -> anyhow::Error {
    match e {
        zbus::Error::MethodError(name, message, _) => {
            let name = name.as_str();
            if name.ends_with("ServiceUnknown") || name.ends_with("NameHasNoOwner") {
                anyhow!("glassd chưa chạy. Thử: systemctl --user start glassd")
            } else {
                anyhow!(message.unwrap_or_else(|| name.to_string()))
            }
        }
        other => anyhow!(other),
    }
}

fn get(proxy: &SettingsProxyBlocking<'_>, key: &str) -> anyhow::Result<Scalar> {
    let value: Value<'_> = proxy.get(key).map_err(explain)?.into();
    scalar(&value)
}

fn set(proxy: &SettingsProxyBlocking<'_>, key: &str, text: &str) -> anyhow::Result<()> {
    let current = get(proxy, key)?;
    let value = Scalar::parse_as(text, &current).map_err(|e| anyhow!("{key}: {e}"))?;
    proxy.set(key, &to_value(&value)).map_err(explain)
}

fn watch(conn: &Connection) -> anyhow::Result<()> {
    let proxy = SettingsProxyBlocking::new(conn)?;
    let errors = SettingsProxyBlocking::new(conn)?;
    let changes = proxy.receive_changed()?;
    let file_errors = errors.receive_file_error()?;

    std::thread::spawn(move || {
        for signal in file_errors {
            if let Ok(args) = signal.args() {
                eprintln!("! {}", args.message());
            }
        }
    });
    for signal in changes {
        let args = signal.args()?;
        println!("{} = {}", args.key(), scalar(args.value())?);
    }
    Ok(())
}

fn run(cli: Cli) -> anyhow::Result<()> {
    let conn = Connection::session().context("không kết nối được session bus")?;
    let proxy = SettingsProxyBlocking::new(&conn)?;

    match cli.command {
        Command::Get { key: Some(key) } => {
            println!("{}", plain(&get(&proxy, &key)?));
        }
        Command::Get { key: None } => {
            let all: BTreeMap<_, _> = proxy.get_all().map_err(explain)?.into_iter().collect();
            for (key, value) in all {
                println!("{key} = {}", scalar(&value)?);
            }
        }
        Command::Set { key, value } => set(&proxy, &key, &value)?,
        Command::Reset { key } => proxy.reset(&key).map_err(explain)?,
        Command::Palettes => {
            let current = plain(&get(&proxy, "appearance.palette")?);
            for name in proxy.list_palettes().map_err(explain)? {
                let mark = if name == current { "*" } else { " " };
                println!("{mark} {name}");
            }
        }
        Command::Palette { name } => proxy.set("appearance.palette", &Value::from(name)).map_err(explain)?,
        Command::Wallpaper { path } => {
            if path == "default" {
                proxy.reset("wallpaper.path").map_err(explain)?;
            } else {
                let absolute = std::fs::canonicalize(&path).with_context(|| format!("không thấy {path}"))?;
                let absolute = absolute.to_str().ok_or_else(|| anyhow!("đường dẫn không phải UTF-8"))?;
                proxy.set("wallpaper.path", &Value::from(absolute)).map_err(explain)?;
            }
        }
        Command::Reload => proxy.reload().map_err(explain)?,
        Command::Watch => watch(&conn)?,
    }
    Ok(())
}

fn main() -> ExitCode {
    // Giữ các hằng này cùng nguồn với glassd.
    debug_assert_eq!(DBUS_NAME, "io.github.canxphung.Glass1");
    debug_assert_eq!(DBUS_PATH, "/io/github/canxphung/Glass1");
    debug_assert_eq!(DBUS_INTERFACE, "io.github.canxphung.Glass1.Settings");

    match run(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("glassctl: {e:#}");
            ExitCode::FAILURE
        }
    }
}
