//! Hỏi người dùng qua shell.
//!
//! Agent của NetworkManager (mật khẩu Wi-Fi) và BlueZ (ghép nối) chạy trong
//! glassd, nhưng hộp thoại do shell vẽ. Agent gọi [`Prompts::ask`]; yêu cầu
//! được phát tới các client socket đã nhận vai hiện hộp thoại (method
//! `handle_prompts`), và câu trả lời quay về qua `prompt_reply` hoặc
//! `prompt_cancel`. Tài liệu giao thức: docs/ipc.md.

use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use serde::Serialize;
use tokio::sync::{Mutex, broadcast, oneshot};
use tracing::{debug, info};

/// Việc cần hỏi. Mỗi loại là một kiểu hộp thoại trong shell.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Prompt {
    /// Mật khẩu (hoặc tên đăng nhập + mật khẩu) cho một mạng Wi-Fi.
    WifiSecrets {
        ssid: String,
        /// "psk", "wep", "enterprise".
        security: String,
        /// Tên các trường cần điền, vd. ["psk"] hay ["identity", "password"].
        fields: Vec<String>,
        /// Lần trước sai mật khẩu, NetworkManager hỏi lại.
        retry: bool,
    },
    /// Ghép nối hoặc cho phép một thiết bị Bluetooth.
    Bluetooth {
        /// "confirm", "authorize", "authorize_service", "pin", "passkey",
        /// "display_pin", "display_passkey".
        action: String,
        /// Đường dẫn D-Bus của thiết bị (org.bluez.Device1).
        device: String,
        name: String,
        /// Mã để so hoặc để gõ trên thiết bị, với các action có mã.
        #[serde(skip_serializing_if = "Option::is_none")]
        code: Option<String>,
        /// UUID dịch vụ, với authorize_service.
        #[serde(skip_serializing_if = "Option::is_none")]
        service: Option<String>,
    },
}

/// Sự kiện gửi tới shell.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum PromptEvent {
    /// Hiện hộp thoại. `wait` là false với hộp thoại chỉ để xem (hiện mã
    /// ghép nối): không cần trả lời, tự đóng khi có `prompt_closed`.
    Prompt {
        id: u64,
        wait: bool,
        #[serde(flatten)]
        prompt: Prompt,
    },
    /// Đóng hộp thoại: đã được trả lời ở client khác, bị huỷ từ phía hệ
    /// thống, hoặc hết giờ.
    PromptClosed { id: u64 },
}

/// Câu trả lời của người dùng: tên trường → giá trị.
pub type Answer = BTreeMap<String, String>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum PromptError {
    #[error("không có shell nào để hỏi")]
    NoUi,
    #[error("người dùng đã huỷ")]
    Canceled,
    #[error("hết giờ chờ trả lời")]
    Timeout,
}

/// Hộp thoại đang chờ trả lời, từ [`Prompts::begin`].
pub struct Ticket {
    pub id: u64,
    rx: oneshot::Receiver<Result<Answer, PromptError>>,
}

struct Pending {
    prompt: Prompt,
    /// None với hộp thoại chỉ để xem.
    reply: Option<oneshot::Sender<Result<Answer, PromptError>>>,
}

pub struct Prompts {
    next_id: AtomicU64,
    ui_clients: AtomicUsize,
    pending: Mutex<HashMap<u64, Pending>>,
    events: broadcast::Sender<PromptEvent>,
}

impl Default for Prompts {
    fn default() -> Self {
        let (events, _) = broadcast::channel(32);
        Self {
            next_id: AtomicU64::new(1),
            ui_clients: AtomicUsize::new(0),
            pending: Mutex::new(HashMap::new()),
            events,
        }
    }
}

impl Prompts {
    pub fn subscribe(&self) -> broadcast::Receiver<PromptEvent> {
        self.events.subscribe()
    }

    pub fn has_ui(&self) -> bool {
        self.ui_clients.load(Ordering::SeqCst) > 0
    }

    /// Một client socket nhận vai hiện hộp thoại. Trả về các hộp thoại đang
    /// mở để client vẽ lại (vd. shell vừa khởi động lại giữa chừng).
    pub async fn attach_ui(&self) -> Vec<PromptEvent> {
        self.ui_clients.fetch_add(1, Ordering::SeqCst);
        let pending = self.pending.lock().await;
        let mut open: Vec<_> = pending
            .iter()
            .map(|(id, p)| PromptEvent::Prompt {
                id: *id,
                wait: p.reply.is_some(),
                prompt: p.prompt.clone(),
            })
            .collect();
        open.sort_by_key(|e| match e {
            PromptEvent::Prompt { id, .. } | PromptEvent::PromptClosed { id } => *id,
        });
        open
    }

    pub fn detach_ui(&self) {
        self.ui_clients.fetch_sub(1, Ordering::SeqCst);
    }

    /// Hỏi và chờ trả lời tối đa `timeout`.
    pub async fn ask(&self, prompt: Prompt, timeout: Duration) -> Result<Answer, PromptError> {
        let ticket = self.begin(prompt).await?;
        self.wait(ticket, timeout).await
    }

    /// Mở hộp thoại cần trả lời. Người gọi giữ `ticket.id` để có thể huỷ
    /// (vd. NetworkManager gọi CancelGetSecrets) rồi gọi [`Self::wait`].
    pub async fn begin(&self, prompt: Prompt) -> Result<Ticket, PromptError> {
        let (tx, rx) = oneshot::channel();
        let id = self.open(prompt, Some(tx)).await?;
        Ok(Ticket { id, rx })
    }

    pub async fn wait(&self, ticket: Ticket, timeout: Duration) -> Result<Answer, PromptError> {
        let Ticket { id, rx } = ticket;
        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(result)) => result,
            // Kênh đóng mà không có trả lời: coi như huỷ.
            Ok(Err(_)) => Err(PromptError::Canceled),
            Err(_) => {
                info!("hộp thoại {id} hết giờ");
                self.close(id, PromptError::Timeout).await;
                Err(PromptError::Timeout)
            }
        }
    }

    /// Hiện hộp thoại chỉ để xem; trả về id để đóng sau bằng [`Self::close`].
    pub async fn show(&self, prompt: Prompt) -> Result<u64, PromptError> {
        self.open(prompt, None).await
    }

    async fn open(
        &self,
        prompt: Prompt,
        reply: Option<oneshot::Sender<Result<Answer, PromptError>>>,
    ) -> Result<u64, PromptError> {
        if !self.has_ui() {
            return Err(PromptError::NoUi);
        }
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let wait = reply.is_some();
        self.pending.lock().await.insert(
            id,
            Pending {
                prompt: prompt.clone(),
                reply,
            },
        );
        debug!("hộp thoại {id}: {prompt:?}");
        let _ = self.events.send(PromptEvent::Prompt { id, wait, prompt });
        Ok(id)
    }

    /// Người dùng trả lời (từ socket).
    pub async fn answer(&self, id: u64, answer: Answer) -> bool {
        self.finish(id, Ok(answer)).await
    }

    /// Đóng một hộp thoại mà không có câu trả lời.
    pub async fn close(&self, id: u64, reason: PromptError) -> bool {
        self.finish(id, Err(reason)).await
    }

    /// Đóng mọi hộp thoại thoả điều kiện, vd. mọi hộp thoại Bluetooth khi
    /// BlueZ gọi Cancel.
    pub async fn close_where(&self, reason: PromptError, matches: impl Fn(&Prompt) -> bool) {
        let ids: Vec<u64> = {
            let pending = self.pending.lock().await;
            pending
                .iter()
                .filter(|(_, p)| matches(&p.prompt))
                .map(|(id, _)| *id)
                .collect()
        };
        for id in ids {
            self.close(id, reason).await;
        }
    }

    async fn finish(&self, id: u64, result: Result<Answer, PromptError>) -> bool {
        let Some(pending) = self.pending.lock().await.remove(&id) else {
            return false;
        };
        if let Some(reply) = pending.reply {
            let _ = reply.send(result);
        }
        let _ = self.events.send(PromptEvent::PromptClosed { id });
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wifi() -> Prompt {
        Prompt::WifiSecrets {
            ssid: "Quán cà phê".into(),
            security: "psk".into(),
            fields: vec!["psk".into()],
            retry: false,
        }
    }

    #[tokio::test]
    async fn no_ui_is_rejected_immediately() {
        let prompts = Prompts::default();
        assert_eq!(
            prompts.ask(wifi(), Duration::from_secs(5)).await,
            Err(PromptError::NoUi)
        );
    }

    #[tokio::test]
    async fn answer_reaches_asker_and_closes_dialog() {
        let prompts = std::sync::Arc::new(Prompts::default());
        prompts.attach_ui().await;
        let mut events = prompts.subscribe();

        let asker = {
            let prompts = prompts.clone();
            tokio::spawn(async move { prompts.ask(wifi(), Duration::from_secs(5)).await })
        };

        let PromptEvent::Prompt { id, wait, prompt } = events.recv().await.unwrap() else {
            panic!("cần sự kiện prompt");
        };
        assert!(wait);
        assert_eq!(prompt, wifi());
        let json = serde_json::to_value(PromptEvent::Prompt {
            id,
            wait,
            prompt: prompt.clone(),
        })
        .unwrap();
        assert_eq!(json["event"], "prompt");
        assert_eq!(json["kind"], "wifi_secrets");
        assert_eq!(json["ssid"], "Quán cà phê");

        let answer = Answer::from([("psk".to_string(), "mat-khau".to_string())]);
        assert!(prompts.answer(id, answer.clone()).await);
        assert_eq!(asker.await.unwrap(), Ok(answer));
        assert!(matches!(
            events.recv().await.unwrap(),
            PromptEvent::PromptClosed { id: closed } if closed == id
        ));
        // Trả lời lần hai (vd. từ client thứ hai) không làm gì.
        assert!(!prompts.answer(id, Answer::new()).await);
    }

    #[tokio::test]
    async fn timeout_and_cancel() {
        let prompts = std::sync::Arc::new(Prompts::default());
        prompts.attach_ui().await;

        assert_eq!(
            prompts.ask(wifi(), Duration::from_millis(50)).await,
            Err(PromptError::Timeout)
        );
        assert!(prompts.attach_ui().await.is_empty(), "hộp thoại hết giờ phải được đóng");

        let asker = {
            let prompts = prompts.clone();
            tokio::spawn(async move { prompts.ask(wifi(), Duration::from_secs(5)).await })
        };
        tokio::time::sleep(Duration::from_millis(20)).await;
        prompts
            .close_where(PromptError::Canceled, |p| matches!(p, Prompt::WifiSecrets { .. }))
            .await;
        assert_eq!(asker.await.unwrap(), Err(PromptError::Canceled));
    }

    #[tokio::test]
    async fn reattached_ui_sees_open_dialogs() {
        let prompts = std::sync::Arc::new(Prompts::default());
        prompts.attach_ui().await;
        let _asker = {
            let prompts = prompts.clone();
            tokio::spawn(async move { prompts.ask(wifi(), Duration::from_secs(5)).await })
        };
        tokio::time::sleep(Duration::from_millis(20)).await;
        prompts.detach_ui();

        let open = prompts.attach_ui().await;
        assert_eq!(open.len(), 1);
        assert!(matches!(&open[0], PromptEvent::Prompt { prompt, .. } if *prompt == wifi()));
    }
}
