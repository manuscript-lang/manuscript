//! WebSocket frames (RFC 6455) and permessage-deflate (RFC 7692, no context takeover).
//!
//! [`Decoder`] is a resumable, pure state machine: push bytes in, pull [`Event`]s out. It
//! reproduces the checks of gorilla's `advanceFrame` in the same order and with the same
//! texts, because the Go runtime surfaces them. Encoding helpers build whole frames.

use flate2::{Compress, Compression, Decompress, FlushCompress, FlushDecompress, Status};
use ring::rand::{SecureRandom, SystemRandom};

pub const OP_CONTINUATION: u8 = 0;
pub const OP_TEXT: u8 = 1;
pub const OP_BINARY: u8 = 2;
pub const OP_CLOSE: u8 = 8;
pub const OP_PING: u8 = 9;
pub const OP_PONG: u8 = 10;

/// Largest payload of a control frame.
pub const MAX_CONTROL_PAYLOAD: usize = 125;

/// Close status codes (RFC 6455 section 7.4.1).
pub mod code {
    pub const NORMAL: u16 = 1000;
    pub const GOING_AWAY: u16 = 1001;
    pub const PROTOCOL_ERROR: u16 = 1002;
    pub const UNSUPPORTED_DATA: u16 = 1003;
    pub const NO_STATUS: u16 = 1005;
    pub const ABNORMAL: u16 = 1006;
    pub const INVALID_PAYLOAD: u16 = 1007;
    pub const POLICY_VIOLATION: u16 = 1008;
    pub const MESSAGE_TOO_BIG: u16 = 1009;
    pub const MANDATORY_EXTENSION: u16 = 1010;
    pub const INTERNAL_ERROR: u16 = 1011;
    pub const SERVICE_RESTART: u16 = 1012;
    pub const TRY_AGAIN_LATER: u16 = 1013;
    pub const TLS_HANDSHAKE: u16 = 1015;
}

/// Whether a close code may appear on the wire (gorilla's `isValidReceivedCloseCode`).
pub fn valid_received_close_code(c: u16) -> bool {
    matches!(
        c,
        code::NORMAL
            | code::GOING_AWAY
            | code::PROTOCOL_ERROR
            | code::UNSUPPORTED_DATA
            | code::INVALID_PAYLOAD
            | code::POLICY_VIOLATION
            | code::MESSAGE_TOO_BIG
            | code::MANDATORY_EXTENSION
            | code::INTERNAL_ERROR
            | code::SERVICE_RESTART
            | code::TRY_AGAIN_LATER
    ) || (3000..=4999).contains(&c)
}

/// gorilla's `CloseError.Error()`: `websocket: close 1006 (abnormal closure): unexpected EOF`.
pub fn close_error_text(c: u16, reason: &str) -> String {
    let name = match c {
        code::NORMAL => " (normal)",
        code::GOING_AWAY => " (going away)",
        code::PROTOCOL_ERROR => " (protocol error)",
        code::UNSUPPORTED_DATA => " (unsupported data)",
        code::NO_STATUS => " (no status)",
        code::ABNORMAL => " (abnormal closure)",
        code::INVALID_PAYLOAD => " (invalid payload data)",
        code::POLICY_VIOLATION => " (policy violation)",
        code::MESSAGE_TOO_BIG => " (message too big)",
        code::MANDATORY_EXTENSION => " (mandatory extension missing)",
        code::INTERNAL_ERROR => " (internal server error)",
        code::TLS_HANDSHAKE => " (TLS handshake error)",
        _ => "",
    };
    let mut s = format!("websocket: close {c}{name}");
    if !reason.is_empty() {
        s.push_str(": ");
        s.push_str(reason);
    }
    s
}

/// `FormatCloseMessage`: two code bytes then the reason; code 1005 has no payload.
pub fn format_close(c: u16, reason: &str) -> Vec<u8> {
    if c == code::NO_STATUS {
        return Vec::new();
    }
    let mut out = c.to_be_bytes().to_vec();
    out.extend_from_slice(reason.as_bytes());
    out
}

/// The payload gorilla sends for a protocol error: 1002 and the message, cut to 125 bytes.
pub fn protocol_error_payload(message: &str) -> Vec<u8> {
    let mut data = format_close(code::PROTOCOL_ERROR, message);
    data.truncate(MAX_CONTROL_PAYLOAD);
    data
}

/// XORs `data` with the mask `key` starting at key offset `pos`; returns the next offset.
pub fn mask_bytes(key: [u8; 4], pos: usize, data: &mut [u8]) -> usize {
    let mut rotated = [0u8; 4];
    for (i, k) in rotated.iter_mut().enumerate() {
        *k = key[(pos + i) & 3];
    }
    let (chunks, tail) = data.as_chunks_mut::<4>();
    for chunk in chunks {
        for (b, k) in chunk.iter_mut().zip(rotated) {
            *b ^= k;
        }
    }
    for (b, k) in tail.iter_mut().zip(rotated) {
        *b ^= k;
    }
    (pos + data.len()) & 3
}

/// A fresh masking key.
pub fn new_mask_key() -> [u8; 4] {
    let mut key = [0u8; 4];
    if SystemRandom::new().fill(&mut key).is_err() {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.subsec_nanos());
        key = nanos.to_le_bytes();
    }
    key
}

/// One frame. A masked frame (`mask` is `Some`) carries the payload XORed with the key.
pub fn encode_frame(
    opcode: u8,
    fin: bool,
    rsv1: bool,
    payload: &[u8],
    mask: Option<[u8; 4]>,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(payload.len() + 14);
    let mut b0 = opcode & 0x0f;
    if fin {
        b0 |= 0x80;
    }
    if rsv1 {
        b0 |= 0x40;
    }
    let mask_bit = if mask.is_some() { 0x80 } else { 0 };
    out.push(b0);
    let len = payload.len();
    if len < 126 {
        out.push(mask_bit | len as u8);
    } else if len <= 0xffff {
        out.push(mask_bit | 126);
        out.extend_from_slice(&(len as u16).to_be_bytes());
    } else {
        out.push(mask_bit | 127);
        out.extend_from_slice(&(len as u64).to_be_bytes());
    }
    let start = match mask {
        Some(key) => {
            out.extend_from_slice(&key);
            out.len()
        }
        None => out.len(),
    };
    out.extend_from_slice(payload);
    if let Some(key) = mask {
        mask_bytes(key, 0, &mut out[start..]);
    }
    out
}

/// A control frame; `None` when the payload exceeds 125 bytes (gorilla's
/// `errInvalidControlFrame`).
pub fn encode_control(opcode: u8, payload: &[u8], masked: bool) -> Option<Vec<u8>> {
    if payload.len() > MAX_CONTROL_PAYLOAD {
        return None;
    }
    let mask = masked.then(new_mask_key);
    Some(encode_frame(opcode, true, false, payload, mask))
}

/// A whole data message as one or more frames. `compress` deflates the payload and sets RSV1
/// on the first frame; `max_frame` splits the (possibly compressed) payload into fragments
/// of at most that many bytes (`0` sends a single frame). Each frame of a client gets its
/// own masking key.
pub fn encode_message(
    opcode: u8,
    payload: &[u8],
    masked: bool,
    compress: bool,
    max_frame: usize,
) -> Vec<u8> {
    let deflated;
    let body = if compress {
        deflated = deflate_message(payload);
        deflated.as_slice()
    } else {
        payload
    };
    let size = if max_frame == 0 {
        body.len().max(1)
    } else {
        max_frame
    };
    let mut out = Vec::with_capacity(body.len() + 14);
    let mut chunks = body.chunks(size).peekable();
    let mut first = true;
    if chunks.peek().is_none() {
        let mask = masked.then(new_mask_key);
        return encode_frame(opcode, true, compress, &[], mask);
    }
    while let Some(chunk) = chunks.next() {
        let op = if first { opcode } else { OP_CONTINUATION };
        let mask = masked.then(new_mask_key);
        let frame = encode_frame(op, chunks.peek().is_none(), first && compress, chunk, mask);
        out.extend_from_slice(&frame);
        first = false;
    }
    out
}

const SYNC_TAIL: [u8; 4] = [0x00, 0x00, 0xff, 0xff];
/// What gorilla appends before inflating: an empty stored block, then a final empty block.
const INFLATE_TAIL: [u8; 9] = [0x00, 0x00, 0xff, 0xff, 0x01, 0x00, 0x00, 0xff, 0xff];
/// Gorilla's `defaultCompressionLevel`.
const DEFLATE_LEVEL: u32 = 1;

/// Raw-deflates one message with a sync flush and strips the trailing `00 00 ff ff`
/// (RFC 7692 section 7.2.1), with no context carried to the next message.
pub fn deflate_message(data: &[u8]) -> Vec<u8> {
    let mut c = Compress::new(Compression::new(DEFLATE_LEVEL), false);
    let mut out: Vec<u8> = Vec::with_capacity(data.len() / 2 + 64);
    loop {
        let consumed = c.total_in() as usize;
        out.reserve(256);
        // Sync flushes on a growable buffer cannot fail; stop rather than loop on a bug.
        if c.compress_vec(&data[consumed..], &mut out, FlushCompress::Sync)
            .is_err()
        {
            break;
        }
        if c.total_in() as usize == data.len() && out.len() < out.capacity() {
            break;
        }
    }
    if out.ends_with(&SYNC_TAIL) {
        out.truncate(out.len() - SYNC_TAIL.len());
    }
    out
}

/// Why a compressed message could not be inflated.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InflateError {
    /// The output exceeds the limit.
    Overflow,
    /// Not a valid deflate stream.
    Corrupt,
}

/// Inflates a message payload as gorilla does: appends the sync tail and a final empty block
/// and reads to the end, failing as soon as the output passes `max` bytes.
pub fn inflate_message(data: &[u8], max: u64) -> Result<Vec<u8>, InflateError> {
    let mut input = Vec::with_capacity(data.len() + INFLATE_TAIL.len());
    input.extend_from_slice(data);
    input.extend_from_slice(&INFLATE_TAIL);
    let mut d = Decompress::new(false);
    let mut out: Vec<u8> = Vec::with_capacity(data.len().saturating_mul(2).min(1 << 20));
    loop {
        let (in_before, out_before) = (d.total_in(), d.total_out());
        out.reserve(32 * 1024);
        let status = d
            .decompress_vec(
                &input[in_before as usize..],
                &mut out,
                FlushDecompress::None,
            )
            .map_err(|_| InflateError::Corrupt)?;
        if out.len() as u64 > max {
            return Err(InflateError::Overflow);
        }
        if status == Status::StreamEnd {
            return Ok(out);
        }
        if d.total_in() == in_before && d.total_out() == out_before {
            return Err(InflateError::Corrupt);
        }
    }
}

/// A decoded unit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    /// A complete data message, decompressed. Text payloads are not yet checked for UTF-8.
    Message {
        text: bool,
        data: Vec<u8>,
    },
    Ping(Vec<u8>),
    Pong(Vec<u8>),
    /// A close frame; `code` is 1005 when it carried none.
    Close {
        code: u16,
        reason: String,
    },
}

/// A failure of the stream. `body` is true when it happened after the first frame of a data
/// message was accepted; gorilla reports those through the message reader, and the Go runtime
/// words them as a truncated exchange.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DecodeError {
    /// A protocol violation. The peer is sent close 1002 with the text (see
    /// [`protocol_error_payload`]); the error reads `websocket: <text>`.
    Protocol { text: String, body: bool },
    /// The message passed the read limit (`websocket: read limit exceeded`). `reply_close`
    /// asks for close 1009 to be sent first.
    Limit { reply_close: bool, body: bool },
    /// A compressed message inflated past the limit.
    Overflow,
    /// A compressed message was not valid deflate data.
    Corrupt,
}

struct Frame {
    opcode: u8,
    fin: bool,
    mask: Option<[u8; 4]>,
    remaining: u64,
    mask_pos: usize,
    control: Vec<u8>,
}

enum Stage {
    Header,
    Payload(Frame),
}

/// Reads frames the way gorilla's `Conn` does for one direction.
pub struct Decoder {
    /// Reading as the server: frames must be masked (and must not be, for a client).
    server: bool,
    deflate: bool,
    limit: u64,
    input: Vec<u8>,
    start: usize,
    stage: Stage,
    /// A data message is split and not yet finished (gorilla's `!readFinal`).
    fragmenting: bool,
    /// The first frame of the current message has been accepted.
    in_body: bool,
    kind: u8,
    compressed: bool,
    wire_len: u64,
    message: Vec<u8>,
}

impl Decoder {
    /// `server` is true when this end is the server; `limit` bounds a message in bytes (on the
    /// wire per frame sum, and after inflation).
    pub fn new(server: bool, deflate: bool, limit: u64) -> Decoder {
        Decoder {
            server,
            deflate,
            limit,
            input: Vec::new(),
            start: 0,
            stage: Stage::Header,
            fragmenting: false,
            in_body: false,
            kind: OP_BINARY,
            compressed: false,
            wire_len: 0,
            message: Vec::new(),
        }
    }

    /// Appends received bytes.
    pub fn push(&mut self, bytes: &[u8]) {
        if self.start > 0 && self.start == self.input.len() {
            self.input.clear();
            self.start = 0;
        } else if self.start > (1 << 16) {
            self.input.drain(..self.start);
            self.start = 0;
        }
        self.input.extend_from_slice(bytes);
    }

    /// Whether the first frame of a data message was accepted and the message is unfinished.
    /// End of stream in that state is worded as a truncated exchange.
    pub fn in_message(&self) -> bool {
        self.in_body
    }

    fn available(&self) -> &[u8] {
        &self.input[self.start..]
    }

    fn protocol(&self, text: impl Into<String>) -> DecodeError {
        DecodeError::Protocol {
            text: text.into(),
            body: self.in_body,
        }
    }

    /// Pulls the next event; `Ok(None)` means more bytes are needed.
    pub fn poll(&mut self) -> Result<Option<Event>, DecodeError> {
        loop {
            if matches!(self.stage, Stage::Header) {
                if !self.header()? {
                    return Ok(None);
                }
                continue;
            }
            match self.payload()? {
                Progress::Wait => return Ok(None),
                Progress::Frame => continue,
                Progress::Event(event) => return Ok(Some(event)),
            }
        }
    }

    /// Parses one frame header if it is complete; true when a frame began.
    fn header(&mut self) -> Result<bool, DecodeError> {
        let avail = self.available();
        if avail.len() < 2 {
            return Ok(false);
        }
        let (b0, b1) = (avail[0], avail[1]);
        let opcode = b0 & 0x0f;
        let fin = b0 & 0x80 != 0;
        let masked = b1 & 0x80 != 0;
        let short = b1 & 0x7f;
        self.check_first_two(b0, b1)?;
        let ext = match short {
            126 => 2,
            127 => 8,
            _ => 0,
        };
        let total = 2 + ext + if masked { 4 } else { 0 };
        if avail.len() < total {
            return Ok(false);
        }
        let length = match short {
            126 => u64::from(u16::from_be_bytes([avail[2], avail[3]])),
            127 => {
                let mut b = [0u8; 8];
                b.copy_from_slice(&avail[2..10]);
                u64::from_be_bytes(b)
            }
            n => u64::from(n),
        };
        let mut key = [0u8; 4];
        if masked {
            key.copy_from_slice(&avail[2 + ext..total]);
        }
        if length > i64::MAX as u64 {
            return Err(DecodeError::Limit {
                reply_close: false,
                body: self.in_body,
            });
        }
        let compressed = b0 & 0x40 != 0 && self.deflate;
        let is_data = opcode != OP_CLOSE && opcode != OP_PING && opcode != OP_PONG;
        if is_data {
            self.accept_data_header(opcode, length, compressed)?;
        }
        self.fragmenting_after(opcode, fin);
        self.start += total;
        self.stage = Stage::Payload(Frame {
            opcode,
            fin,
            mask: masked.then_some(key),
            remaining: length,
            mask_pos: 0,
            control: Vec::new(),
        });
        Ok(true)
    }

    /// Updates the split-message flag once a header is fully accepted.
    fn fragmenting_after(&mut self, opcode: u8, fin: bool) {
        if opcode == OP_TEXT || opcode == OP_BINARY || opcode == OP_CONTINUATION {
            self.fragmenting = !fin;
        }
    }

    /// gorilla's checks on the first two header bytes, run before the rest of the header is
    /// awaited, collecting every reason into one comma-separated text.
    fn check_first_two(&self, b0: u8, b1: u8) -> Result<(), DecodeError> {
        let opcode = b0 & 0x0f;
        let fin = b0 & 0x80 != 0;
        let mut reasons: Vec<String> = Vec::new();
        if b0 & 0x40 != 0 && !self.deflate {
            reasons.push("RSV1 set".into());
        }
        if b0 & 0x20 != 0 {
            reasons.push("RSV2 set".into());
        }
        if b0 & 0x10 != 0 {
            reasons.push("RSV3 set".into());
        }
        match opcode {
            OP_CLOSE | OP_PING | OP_PONG => {
                if b1 & 0x7f > MAX_CONTROL_PAYLOAD as u8 {
                    reasons.push("len > 125 for control".into());
                }
                if !fin {
                    reasons.push("FIN not set on control".into());
                }
            }
            OP_TEXT | OP_BINARY => {
                if self.fragmenting {
                    reasons.push("data before FIN".into());
                }
            }
            OP_CONTINUATION => {
                if !self.fragmenting {
                    reasons.push("continuation after FIN".into());
                }
            }
            other => reasons.push(format!("bad opcode {other}")),
        }
        if (b1 & 0x80 != 0) != self.server {
            reasons.push("bad MASK".into());
        }
        if reasons.is_empty() {
            Ok(())
        } else {
            Err(self.protocol(reasons.join(", ")))
        }
    }

    /// Message-size accounting of a data frame; starts a new message on a text or binary one.
    fn accept_data_header(
        &mut self,
        opcode: u8,
        length: u64,
        compressed: bool,
    ) -> Result<(), DecodeError> {
        let starts = opcode != OP_CONTINUATION;
        let base = if starts { 0 } else { self.wire_len };
        let wire = base
            .checked_add(length)
            .filter(|w| *w <= i64::MAX as u64)
            .ok_or(DecodeError::Limit {
                reply_close: false,
                body: self.in_body,
            })?;
        if wire > self.limit {
            return Err(DecodeError::Limit {
                reply_close: true,
                body: self.in_body,
            });
        }
        self.wire_len = wire;
        if starts {
            self.kind = opcode;
            self.compressed = compressed;
            self.message.clear();
            self.in_body = true;
        }
        Ok(())
    }

    fn payload(&mut self) -> Result<Progress, DecodeError> {
        let Stage::Payload(frame) = &mut self.stage else {
            return Ok(Progress::Frame);
        };
        let avail = self.input.len() - self.start;
        let take = (avail as u64).min(frame.remaining) as usize;
        if take > 0 {
            let chunk = &self.input[self.start..self.start + take];
            let control = frame.opcode >= OP_CLOSE;
            let sink = if control {
                &mut frame.control
            } else {
                &mut self.message
            };
            let from = sink.len();
            sink.extend_from_slice(chunk);
            if let Some(key) = frame.mask {
                frame.mask_pos = mask_bytes(key, frame.mask_pos, &mut sink[from..]);
            }
            frame.remaining -= take as u64;
            self.start += take;
        }
        if frame.remaining > 0 {
            return Ok(Progress::Wait);
        }
        let opcode = frame.opcode;
        let fin = frame.fin;
        let control = std::mem::take(&mut frame.control);
        self.stage = Stage::Header;
        if opcode >= OP_CLOSE {
            return self.control_event(opcode, control);
        }
        if !fin {
            return Ok(Progress::Frame);
        }
        self.finish_message()
    }

    fn control_event(&mut self, opcode: u8, payload: Vec<u8>) -> Result<Progress, DecodeError> {
        let event = match opcode {
            OP_PING => Event::Ping(payload),
            OP_PONG => Event::Pong(payload),
            _ => self.close_event(&payload)?,
        };
        Ok(Progress::Event(event))
    }

    fn close_event(&self, payload: &[u8]) -> Result<Event, DecodeError> {
        if payload.len() < 2 {
            return Ok(Event::Close {
                code: code::NO_STATUS,
                reason: String::new(),
            });
        }
        let c = u16::from_be_bytes([payload[0], payload[1]]);
        if !valid_received_close_code(c) {
            return Err(self.protocol(format!("bad close code {c}")));
        }
        let Ok(reason) = std::str::from_utf8(&payload[2..]) else {
            return Err(self.protocol("invalid utf8 payload in close frame"));
        };
        Ok(Event::Close {
            code: c,
            reason: reason.to_string(),
        })
    }

    fn finish_message(&mut self) -> Result<Progress, DecodeError> {
        self.in_body = false;
        let raw = std::mem::take(&mut self.message);
        let data = if self.compressed {
            inflate_message(&raw, self.limit).map_err(|e| match e {
                InflateError::Overflow => DecodeError::Overflow,
                InflateError::Corrupt => DecodeError::Corrupt,
            })?
        } else {
            raw
        };
        Ok(Progress::Event(Event::Message {
            text: self.kind == OP_TEXT,
            data,
        }))
    }
}

enum Progress {
    /// More input is needed.
    Wait,
    /// A frame ended without an event (a non-final data fragment).
    Frame,
    Event(Event),
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: [u8; 4] = [0x37, 0xfa, 0x21, 0x3d];

    fn decode_all(d: &mut Decoder) -> Vec<Event> {
        let mut out = Vec::new();
        while let Some(e) = d.poll().unwrap() {
            out.push(e);
        }
        out
    }

    fn message(text: bool, data: &[u8]) -> Event {
        Event::Message {
            text,
            data: data.to_vec(),
        }
    }

    #[test]
    fn rfc6455_section_5_7_examples() {
        // Unmasked text "Hello".
        let f = encode_frame(OP_TEXT, true, false, b"Hello", None);
        assert_eq!(f, [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]);
        // Masked text "Hello".
        let f = encode_frame(OP_TEXT, true, false, b"Hello", Some(KEY));
        assert_eq!(
            f,
            [
                0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58
            ]
        );
        let mut server = Decoder::new(true, false, 100);
        server.push(&f);
        assert_eq!(decode_all(&mut server), vec![message(true, b"Hello")]);
        // Fragmented "Hel" + "lo".
        let mut client = Decoder::new(false, false, 100);
        client.push(&[0x01, 0x03, 0x48, 0x65, 0x6c]);
        assert_eq!(decode_all(&mut client), vec![]);
        client.push(&[0x80, 0x02, 0x6c, 0x6f]);
        assert_eq!(decode_all(&mut client), vec![message(true, b"Hello")]);
        // Unmasked ping and masked pong "Hello".
        client.push(&[0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]);
        assert_eq!(
            decode_all(&mut client),
            vec![Event::Ping(b"Hello".to_vec())]
        );
        let pong = [
            0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58,
        ];
        server.push(&pong);
        assert_eq!(
            decode_all(&mut server),
            vec![Event::Pong(b"Hello".to_vec())]
        );
    }

    #[test]
    fn length_forms() {
        let f = encode_frame(OP_BINARY, true, false, &[7u8; 256], None);
        assert_eq!(&f[..4], [0x82, 0x7e, 0x01, 0x00]);
        let f = encode_frame(OP_BINARY, true, false, &vec![7u8; 65536], None);
        assert_eq!(&f[..10], [0x82, 0x7f, 0, 0, 0, 0, 0, 1, 0, 0]);
        let mut d = Decoder::new(false, false, 1 << 20);
        d.push(&f);
        assert_eq!(decode_all(&mut d), vec![message(false, &vec![7u8; 65536])]);
        let edge = encode_frame(OP_BINARY, true, false, &[1u8; 125], None);
        assert_eq!(edge[1], 125);
        let edge = encode_frame(OP_BINARY, true, false, &[1u8; 126], None);
        assert_eq!(&edge[..4], [0x82, 126, 0, 126]);
    }

    #[test]
    fn masking_is_an_involution_at_any_offset() {
        let original: Vec<u8> = (0..37).collect();
        let mut data = original.clone();
        let next = mask_bytes(KEY, 0, &mut data[..5]);
        assert_eq!(next, 1);
        let next = mask_bytes(KEY, next, &mut data[5..]);
        assert_eq!(next, 37 & 3);
        let mut again = data.clone();
        mask_bytes(KEY, 0, &mut again);
        assert_eq!(again, original);
    }

    #[test]
    fn decoding_is_resumable_byte_by_byte() {
        let mut wire = encode_message(OP_TEXT, b"fragmented message", true, false, 5);
        wire.extend(encode_control(OP_PING, b"p", true).unwrap());
        let mut d = Decoder::new(true, false, 100);
        let mut events = Vec::new();
        for b in wire {
            d.push(&[b]);
            while let Some(e) = d.poll().unwrap() {
                events.push(e);
            }
        }
        assert_eq!(
            events,
            vec![
                message(true, b"fragmented message"),
                Event::Ping(b"p".to_vec())
            ]
        );
    }

    #[test]
    fn control_frames_interleave_with_fragments() {
        let mut d = Decoder::new(false, false, 100);
        d.push(&encode_frame(OP_TEXT, false, false, b"ab", None));
        d.push(&encode_frame(OP_PING, true, false, b"x", None));
        d.push(&encode_frame(OP_CONTINUATION, true, false, b"cd", None));
        assert_eq!(
            decode_all(&mut d),
            vec![Event::Ping(b"x".to_vec()), message(true, b"abcd")]
        );
    }

    fn protocol_text(bytes: &[u8], server: bool, deflate: bool) -> String {
        let mut d = Decoder::new(server, deflate, 100);
        d.push(bytes);
        match d.poll() {
            Err(DecodeError::Protocol { text, .. }) => text,
            other => panic!("expected a protocol error, got {other:?}"),
        }
    }

    #[test]
    fn protocol_violations_use_gorilla_texts() {
        let masked = |op, fin, rsv: u8, payload: &[u8]| {
            let mut f = encode_frame(op, fin, false, payload, Some(KEY));
            f[0] |= rsv;
            f
        };
        assert_eq!(
            protocol_text(&masked(OP_TEXT, true, 0x40, b"a"), true, false),
            "RSV1 set"
        );
        assert_eq!(
            protocol_text(&masked(OP_TEXT, true, 0x70, b"a"), true, false),
            "RSV1 set, RSV2 set, RSV3 set"
        );
        assert_eq!(
            protocol_text(&masked(3, true, 0, b""), true, false),
            "bad opcode 3"
        );
        assert_eq!(
            protocol_text(&masked(OP_PING, false, 0, b""), true, false),
            "FIN not set on control"
        );
        assert_eq!(
            protocol_text(&masked(OP_PING, true, 0, &[0; 126]), true, false),
            "len > 125 for control"
        );
        assert_eq!(
            protocol_text(&masked(OP_CONTINUATION, true, 0, b"a"), true, false),
            "continuation after FIN"
        );
        // Unmasked into a server and masked into a client.
        let plain = encode_frame(OP_TEXT, true, false, b"a", None);
        assert_eq!(protocol_text(&plain, true, false), "bad MASK");
        assert_eq!(
            protocol_text(&masked(OP_TEXT, true, 0, b"a"), false, false),
            "bad MASK"
        );
        // Several reasons are joined in gorilla's order.
        assert_eq!(
            protocol_text(&masked(5, false, 0x20, b""), true, false),
            "RSV2 set, bad opcode 5"
        );
        // Validation happens before the rest of the header arrives.
        assert_eq!(
            protocol_text(&[0xff, 0xfe], true, false),
            "RSV1 set, RSV2 set, RSV3 set, bad opcode 15"
        );
    }

    #[test]
    fn data_before_fin() {
        let mut d = Decoder::new(false, false, 100);
        d.push(&encode_frame(OP_TEXT, false, false, b"a", None));
        d.push(&encode_frame(OP_BINARY, true, false, b"b", None));
        let err = d.poll().unwrap_err();
        assert_eq!(
            err,
            DecodeError::Protocol {
                text: "data before FIN".into(),
                body: true
            }
        );
    }

    #[test]
    fn close_frames_are_validated() {
        let close = |payload: &[u8]| {
            let mut d = Decoder::new(false, false, 100);
            d.push(&encode_frame(OP_CLOSE, true, false, payload, None));
            d.poll()
        };
        assert_eq!(
            close(&[]).unwrap(),
            Some(Event::Close {
                code: 1005,
                reason: String::new()
            })
        );
        assert_eq!(
            close(&[0x03]).unwrap(),
            Some(Event::Close {
                code: 1005,
                reason: String::new()
            })
        );
        assert_eq!(
            close(&format_close(1001, "bye")).unwrap(),
            Some(Event::Close {
                code: 1001,
                reason: "bye".into()
            })
        );
        assert_eq!(
            close(&format_close(3999, ""))
                .unwrap()
                .map(|e| matches!(e, Event::Close { code: 3999, .. })),
            Some(true)
        );
        for bad in [1005u16, 1006, 1015, 999, 1004, 1016, 2999, 5000] {
            let Err(DecodeError::Protocol { text, .. }) = close(&bad.to_be_bytes()) else {
                panic!("{bad} accepted");
            };
            assert_eq!(text, format!("bad close code {bad}"));
        }
        let mut payload = format_close(1000, "");
        payload.extend_from_slice(&[0xff, 0xfe]);
        let Err(DecodeError::Protocol { text, .. }) = close(&payload) else {
            panic!("bad utf8 accepted");
        };
        assert_eq!(text, "invalid utf8 payload in close frame");
    }

    #[test]
    fn read_limit_checks_the_wire_length_per_frame() {
        let mut d = Decoder::new(false, false, 8);
        d.push(&encode_frame(OP_BINARY, true, false, &[0; 8], None));
        assert_eq!(decode_all(&mut d), vec![message(false, &[0; 8])]);
        // One over: refused from the header alone, with close 1009 to send.
        let mut d = Decoder::new(false, false, 8);
        d.push(&[0x82, 9]);
        assert_eq!(
            d.poll().unwrap_err(),
            DecodeError::Limit {
                reply_close: true,
                body: false
            }
        );
        // Fragments add up, and the error then belongs to the message body.
        let mut d = Decoder::new(false, false, 8);
        d.push(&encode_frame(OP_BINARY, false, false, &[0; 5], None));
        d.push(&encode_frame(OP_CONTINUATION, true, false, &[0; 4], None));
        assert_eq!(
            d.poll().unwrap_err(),
            DecodeError::Limit {
                reply_close: true,
                body: true
            }
        );
        // A 64-bit length with the top bit set is "read limit exceeded" without a close frame.
        let mut d = Decoder::new(false, false, u64::MAX);
        d.push(&[0x82, 127, 0x80, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(
            d.poll().unwrap_err(),
            DecodeError::Limit {
                reply_close: false,
                body: false
            }
        );
        // Unlimited decoders accept large lengths until the data runs out.
        let mut d = Decoder::new(false, false, u64::MAX);
        d.push(&[0x82, 127, 0, 0, 0, 0, 0, 0x10, 0, 0]);
        assert_eq!(d.poll().unwrap(), None);
        assert!(d.in_message());
    }

    #[test]
    fn deflate_round_trips_and_strips_the_tail() {
        for sample in [&b""[..], b"x", b"hello hello hello", &[0u8; 5000]] {
            let packed = deflate_message(sample);
            assert_eq!(inflate_message(&packed, u64::MAX).unwrap(), sample);
        }
        let big: Vec<u8> = (0..200_000u32).map(|i| (i * 7 + i / 13) as u8).collect();
        assert_eq!(
            inflate_message(&deflate_message(&big), u64::MAX).unwrap(),
            big
        );
        // The empty message is the single byte 00, as in the recorded gorilla output below.
        assert_eq!(deflate_message(b""), [0x00]);
    }

    #[test]
    fn inflates_what_gorilla_wrote() {
        // Recorded by running the vendored gorilla server with compression enabled: the
        // payloads of its RSV1 text frames for "hello hello hello", "" and binary "x".
        let hello: &[u8] = &[
            0x00, 0x11, 0x00, 0xee, 0xff, b'h', b'e', b'l', b'l', b'o', b' ', b'h', b'e', b'l',
            b'l', b'o', b' ', b'h', b'e', b'l', b'l', b'o', 0x00,
        ];
        assert_eq!(inflate_message(hello, 100).unwrap(), b"hello hello hello");
        assert_eq!(inflate_message(&[0x00], 100).unwrap(), b"");
        assert_eq!(
            inflate_message(&[0x00, 0x01, 0x00, 0xfe, 0xff, b'x', 0x00], 100).unwrap(),
            b"x"
        );
        let wire = [&[0xc1u8, 0x17][..], hello].concat();
        let mut d = Decoder::new(false, true, 100);
        d.push(&wire);
        assert_eq!(
            decode_all(&mut d),
            vec![message(true, b"hello hello hello")]
        );
    }

    #[test]
    fn inflate_limit_and_corruption() {
        let packed = deflate_message(&[b'x'; 10_000]);
        assert!(packed.len() < 200);
        assert_eq!(inflate_message(&packed, 128), Err(InflateError::Overflow));
        assert_eq!(inflate_message(&packed, 10_000).unwrap().len(), 10_000);
        assert_eq!(
            inflate_message(&[0xff, 0xff, 0xff], 100),
            Err(InflateError::Corrupt)
        );
        // A decoder with a small limit refuses the small compressed frame once inflated.
        let mut d = Decoder::new(false, true, 128);
        d.push(&encode_message(OP_TEXT, &[b'x'; 10_000], false, true, 0));
        assert_eq!(d.poll().unwrap_err(), DecodeError::Overflow);
    }

    #[test]
    fn compressed_messages_round_trip_through_frames() {
        for max_frame in [0, 7] {
            let wire = encode_message(OP_TEXT, b"compress me, compress me", true, true, max_frame);
            assert_eq!(wire[0] & 0x40, 0x40);
            let mut d = Decoder::new(true, true, 1000);
            d.push(&wire);
            assert_eq!(
                decode_all(&mut d),
                vec![message(true, b"compress me, compress me")]
            );
        }
        // RSV1 is a protocol error when nothing was negotiated.
        let wire = encode_message(OP_TEXT, b"x", false, true, 0);
        assert_eq!(protocol_text(&wire, false, false), "RSV1 set");
    }

    #[test]
    fn encode_helpers() {
        assert!(encode_control(OP_PING, &[0; 126], false).is_none());
        let ping = encode_control(OP_PING, &[1; 125], true).unwrap();
        assert_eq!(ping[1], 0x80 | 125);
        assert_eq!(format_close(1005, "x"), Vec::<u8>::new());
        assert_eq!(format_close(1000, "ok"), [0x03, 0xe8, b'o', b'k']);
        assert_eq!(protocol_error_payload(&"x".repeat(300)).len(), 125);
        assert_eq!(
            close_error_text(1006, "unexpected EOF"),
            "websocket: close 1006 (abnormal closure): unexpected EOF"
        );
        assert_eq!(close_error_text(1000, ""), "websocket: close 1000 (normal)");
        assert_eq!(close_error_text(1012, ""), "websocket: close 1012");
        assert_eq!(close_error_text(4000, "bye"), "websocket: close 4000: bye");
        let empty = encode_message(OP_BINARY, b"", false, false, 0);
        assert_eq!(empty, [0x82, 0x00]);
        // Fragmentation splits at the given size and ends with FIN.
        let parts = encode_message(OP_BINARY, b"abcde", false, false, 2);
        assert_eq!(
            parts,
            [0x02, 2, b'a', b'b', 0x00, 2, b'c', b'd', 0x80, 1, b'e']
        );
    }
}
