//! Framed JSON-RPC input: a reader thread decodes `Content-Length` frames into
//! a bounded queue and tracks cancellation, so the main loop can see that a
//! request was canceled while it was still working.

use crate::json;
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read};
use std::sync::mpsc::{Receiver, SyncSender, sync_channel};
use std::sync::{Arc, Mutex};

const MAX_HEADER: usize = 8192;
const MAX_BODY: usize = 16 << 20;

/// One frame, or the reason input ended.
pub struct Incoming {
    /// The message body.
    pub body: Vec<u8>,
    /// Why reading stopped: `None` for a message.
    pub error: Option<FrameError>,
    /// A `textDocument/didChange` notification, which the server batches.
    pub change: bool,
}

/// How framed input ended.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FrameError {
    /// Clean end of input between messages.
    Eof,
    /// A protocol or I/O failure.
    Failed(String),
}

type Pending = Arc<Mutex<HashMap<String, bool>>>;

/// The receiving half of the input thread.
pub struct Transport {
    /// Decoded messages in arrival order.
    pub messages: Receiver<Incoming>,
    pending: Pending,
}

impl Transport {
    /// Starts reading frames from `input` on a thread of its own.
    pub fn new(input: impl Read + Send + 'static) -> Transport {
        let (sender, messages) = sync_channel(32);
        let pending: Pending = Arc::default();
        let shared = pending.clone();
        std::thread::spawn(move || read_loop(input, sender, shared));
        Transport { messages, pending }
    }

    /// Whether the client canceled the request with this id.
    pub fn canceled(&self, id: &json::Json) -> bool {
        let pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        pending.get(&id.encode()).copied().unwrap_or(false)
    }

    /// Forgets a finished request.
    pub fn done(&self, id: &json::Json) {
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        pending.remove(&id.encode());
    }
}

fn read_loop(input: impl Read, sender: SyncSender<Incoming>, pending: Pending) {
    let mut reader = BufReader::with_capacity(8192, input);
    loop {
        let body = match read_frame(&mut reader) {
            Ok(body) => body,
            Err(error) => {
                let _ = sender.send(Incoming {
                    body: Vec::new(),
                    error: Some(error),
                    change: false,
                });
                return;
            }
        };
        let mut change = false;
        if let Ok(message) = json::parse(&body) {
            let method = message.get("method").and_then(|m| m.as_str());
            if method == Some("$/cancelRequest") {
                if let Some(id) = message.get("params").and_then(|p| p.get("id")) {
                    let mut pending = pending.lock().unwrap_or_else(|e| e.into_inner());
                    if let Some(flag) = pending.get_mut(&id.encode()) {
                        *flag = true;
                    }
                }
                continue;
            }
            let id = message.get("id");
            if let Some(id) = id {
                let mut pending = pending.lock().unwrap_or_else(|e| e.into_inner());
                pending.insert(id.encode(), false);
            }
            change = message.get("jsonrpc").and_then(|v| v.as_str()) == Some("2.0")
                && id.is_none()
                && method == Some("textDocument/didChange");
        }
        if sender
            .send(Incoming {
                body,
                error: None,
                change,
            })
            .is_err()
        {
            return;
        }
    }
}

/// Reads one `Content-Length` frame.
pub fn read_frame(reader: &mut impl BufRead) -> Result<Vec<u8>, FrameError> {
    let failed = |message: &str| FrameError::Failed(message.to_string());
    let mut length: Option<usize> = None;
    let mut header_size = 0;
    loop {
        let mut line = Vec::new();
        let read = reader
            .by_ref()
            .take((MAX_HEADER + 1) as u64)
            .read_until(b'\n', &mut line)
            .map_err(|e| FrameError::Failed(e.to_string()))?;
        header_size += read;
        if header_size > MAX_HEADER {
            return Err(failed("protocol header exceeds 8192 bytes"));
        }
        if read == 0 && length.is_none() && header_size == 0 {
            return Err(FrameError::Eof);
        }
        if line.last() != Some(&b'\n') {
            return Err(failed("unexpected EOF"));
        }
        let text = String::from_utf8_lossy(&line);
        let trimmed = text.trim();
        if trimmed.is_empty() {
            break;
        }
        let Some((key, value)) = trimmed.split_once(':') else {
            return Err(failed("malformed protocol header"));
        };
        if key.eq_ignore_ascii_case("Content-Length") {
            if length.is_some() {
                return Err(failed("duplicate Content-Length"));
            }
            length = Some(
                value
                    .trim()
                    .parse::<i64>()
                    .map_err(|e| FrameError::Failed(e.to_string()))
                    .and_then(|n| {
                        usize::try_from(n).map_err(|_| failed("invalid Content-Length"))
                    })?,
            );
        }
    }
    let length = length.ok_or_else(|| failed("invalid Content-Length"))?;
    if length > MAX_BODY {
        return Err(failed("invalid Content-Length"));
    }
    let mut body = vec![0; length];
    reader
        .read_exact(&mut body)
        .map_err(|e| FrameError::Failed(e.to_string()))?;
    Ok(body)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frames(input: &str) -> Result<Vec<u8>, FrameError> {
        read_frame(&mut input.as_bytes())
    }

    #[test]
    fn reads_a_frame() {
        assert_eq!(frames("Content-Length: 2\r\n\r\n{}").unwrap(), b"{}");
        assert_eq!(frames("content-length:2\r\nX: y\r\n\r\n{}").unwrap(), b"{}");
    }

    #[test]
    fn rejects_bad_frames() {
        for bad in [
            "Content-Length: -1\r\n\r\n",
            "Content-Length: 999999999\r\n\r\n",
            "Content-Length: 20\r\n\r\n{}",
            "Content-Length: 1\r\nContent-Length: 1\r\n\r\nx",
            "NoColon\r\n\r\n",
            "\r\n",
        ] {
            assert!(matches!(frames(bad), Err(FrameError::Failed(_))), "{bad:?}");
        }
        assert_eq!(frames(""), Err(FrameError::Eof));
    }
}
