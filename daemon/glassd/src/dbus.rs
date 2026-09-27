//! API công khai trên session bus: `io.github.canxphung.Glass1`.
//! Tài liệu: docs/ipc.md.

use std::collections::HashMap;
use std::sync::Arc;

use glass_core::settings::Scalar;
use glass_core::{DBUS_NAME, DBUS_PATH};
use tracing::warn;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedValue, Value};
use zbus::{Connection, fdo, interface};

use crate::service::{Event, Service, ServiceError};

pub struct SettingsIface {
    service: Arc<Service>,
}

fn to_value(scalar: &Scalar) -> Value<'static> {
    match scalar {
        Scalar::Bool(b) => Value::from(*b),
        Scalar::Int(i) => Value::from(*i),
        Scalar::Float(f) => Value::from(*f),
        Scalar::Str(s) => Value::from(s.clone()),
    }
}

fn to_owned(scalar: &Scalar) -> OwnedValue {
    OwnedValue::try_from(to_value(scalar)).expect("giá trị đơn luôn chuyển được sang OwnedValue")
}

fn from_value(value: &Value<'_>) -> fdo::Result<Scalar> {
    let int = |i: i64| Ok(Scalar::Int(i));
    match value {
        Value::Bool(b) => Ok(Scalar::Bool(*b)),
        Value::U8(i) => int((*i).into()),
        Value::I16(i) => int((*i).into()),
        Value::U16(i) => int((*i).into()),
        Value::I32(i) => int((*i).into()),
        Value::U32(i) => int((*i).into()),
        Value::I64(i) => int(*i),
        Value::U64(i) => i64::try_from(*i)
            .map(Scalar::Int)
            .map_err(|_| fdo::Error::InvalidArgs("số quá lớn".into())),
        Value::F64(f) => Ok(Scalar::Float(*f)),
        Value::Str(s) => Ok(Scalar::Str(s.to_string())),
        Value::Value(inner) => from_value(inner),
        other => Err(fdo::Error::InvalidArgs(format!(
            "không hỗ trợ kiểu {}",
            other.value_signature()
        ))),
    }
}

fn map_err(e: ServiceError) -> fdo::Error {
    match e {
        ServiceError::Io(_) => fdo::Error::Failed(e.to_string()),
        _ => fdo::Error::InvalidArgs(e.to_string()),
    }
}

#[interface(name = "io.github.canxphung.Glass1.Settings")]
impl SettingsIface {
    /// Giá trị của một khoá, vd. "appearance.palette".
    async fn get(&self, key: &str) -> fdo::Result<OwnedValue> {
        self.service.get(key).await.map(|v| to_owned(&v)).map_err(map_err)
    }

    /// Mọi khoá và giá trị.
    async fn get_all(&self) -> HashMap<String, OwnedValue> {
        self.service
            .get_all()
            .await
            .iter()
            .map(|(k, v)| (k.clone(), to_owned(v)))
            .collect()
    }

    /// Đổi một khoá; ghi settings.toml và áp ngay.
    async fn set(&self, key: &str, value: Value<'_>) -> fdo::Result<()> {
        let scalar = from_value(&value)?;
        self.service.set(key, scalar).await.map_err(map_err)
    }

    /// Đưa một khoá về mặc định.
    async fn reset(&self, key: &str) -> fdo::Result<()> {
        self.service.reset(key).await.map_err(map_err)
    }

    /// Tên các palette có thể chọn.
    async fn list_palettes(&self) -> Vec<String> {
        self.service.palettes()
    }

    /// Đọc lại settings.toml ngay (bình thường glassd tự theo dõi file).
    async fn reload(&self) -> fdo::Result<()> {
        self.service.reload_from_disk().await.map_err(map_err)
    }

    #[zbus(property)]
    async fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").to_string()
    }

    #[zbus(signal)]
    async fn changed(emitter: &SignalEmitter<'_>, key: &str, value: Value<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn file_error(emitter: &SignalEmitter<'_>, message: &str) -> zbus::Result<()>;
}

/// Kết nối session bus, đặt object Settings và phát tín hiệu cho mọi sự
/// kiện của service. Chưa giữ tên: xem [`claim_name`].
pub async fn connect(service: Arc<Service>) -> anyhow::Result<Connection> {
    let mut events = service.subscribe();
    let conn = zbus::connection::Builder::session()?
        .serve_at(DBUS_PATH, SettingsIface { service })?
        .build()
        .await?;

    let emitter = SignalEmitter::new(&conn, DBUS_PATH)?.into_owned();
    tokio::spawn(async move {
        loop {
            let result = match events.recv().await {
                Ok(Event::Changed { key, value }) => SettingsIface::changed(&emitter, &key, to_value(&value)).await,
                Ok(Event::FileError { message }) => SettingsIface::file_error(&emitter, &message).await,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    warn!("bỏ lỡ {n} sự kiện D-Bus");
                    continue;
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            };
            if let Err(e) = result {
                warn!("không phát được tín hiệu D-Bus: {e}");
            }
        }
    });

    Ok(conn)
}

/// Đã có glassd khác giữ tên trên bus chưa.
pub async fn already_running(conn: &Connection) -> anyhow::Result<bool> {
    let bus = fdo::DBusProxy::new(conn).await?;
    Ok(bus.name_has_owner(DBUS_NAME.try_into()?).await?)
}

/// Giữ tên D-Bus. systemd (Type=dbus) coi glassd sẵn sàng từ lúc này.
pub async fn claim_name(conn: &Connection) -> anyhow::Result<()> {
    conn.request_name(DBUS_NAME).await?;
    Ok(())
}
