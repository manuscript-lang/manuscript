//! HTTP/2 frame layer (RFC 7540 section 4 and 6): parsing and serialization.

use super::{H2Error, error_code};

/// Client connection preface (RFC 7540 section 3.5).
pub const PREFACE: &[u8] = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
/// Length of the fixed frame header.
pub const FRAME_HEADER_LEN: usize = 9;
/// Initial and minimum `SETTINGS_MAX_FRAME_SIZE`.
pub const DEFAULT_MAX_FRAME_SIZE: u32 = 16_384;
/// Largest legal `SETTINGS_MAX_FRAME_SIZE`.
pub const MAX_MAX_FRAME_SIZE: u32 = (1 << 24) - 1;
/// Largest flow-control window.
pub const MAX_WINDOW: i64 = 0x7fff_ffff;

pub const TYPE_DATA: u8 = 0x0;
pub const TYPE_HEADERS: u8 = 0x1;
pub const TYPE_PRIORITY: u8 = 0x2;
pub const TYPE_RST_STREAM: u8 = 0x3;
pub const TYPE_SETTINGS: u8 = 0x4;
pub const TYPE_PUSH_PROMISE: u8 = 0x5;
pub const TYPE_PING: u8 = 0x6;
pub const TYPE_GOAWAY: u8 = 0x7;
pub const TYPE_WINDOW_UPDATE: u8 = 0x8;
pub const TYPE_CONTINUATION: u8 = 0x9;

pub const FLAG_END_STREAM: u8 = 0x1;
pub const FLAG_ACK: u8 = 0x1;
pub const FLAG_END_HEADERS: u8 = 0x4;
pub const FLAG_PADDED: u8 = 0x8;
pub const FLAG_PRIORITY: u8 = 0x20;

/// SETTINGS identifiers.
pub const SETTINGS_HEADER_TABLE_SIZE: u16 = 0x1;
pub const SETTINGS_ENABLE_PUSH: u16 = 0x2;
pub const SETTINGS_MAX_CONCURRENT_STREAMS: u16 = 0x3;
pub const SETTINGS_INITIAL_WINDOW_SIZE: u16 = 0x4;
pub const SETTINGS_MAX_FRAME_SIZE: u16 = 0x5;
pub const SETTINGS_MAX_HEADER_LIST_SIZE: u16 = 0x6;

/// A decoded frame. Header blocks stay HPACK-encoded; the connection decodes
/// them once a block is complete.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Frame {
    Data {
        id: u32,
        data: Vec<u8>,
        /// Padding octets including the pad-length field (0 when not padded).
        pad: u32,
        /// Whole payload length, which is what flow control charges.
        flow_len: u32,
        end_stream: bool,
    },
    Headers {
        id: u32,
        block: Vec<u8>,
        end_stream: bool,
        end_headers: bool,
    },
    Priority {
        id: u32,
    },
    RstStream {
        id: u32,
        code: u32,
    },
    Settings {
        ack: bool,
        params: Vec<(u16, u32)>,
    },
    PushPromise {
        id: u32,
        promised: u32,
    },
    Ping {
        ack: bool,
        data: [u8; 8],
    },
    GoAway {
        last_stream_id: u32,
        code: u32,
        debug: Vec<u8>,
    },
    WindowUpdate {
        id: u32,
        /// Raw 31-bit increment; zero is validated by the connection because
        /// the error scope depends on the stream id.
        increment: u32,
    },
    Continuation {
        id: u32,
        block: Vec<u8>,
        end_headers: bool,
    },
    /// Unknown frame types must be ignored (RFC 7540 section 4.1).
    Unknown {
        ty: u8,
    },
}

fn proto(reason: &str) -> H2Error {
    H2Error::connection(error_code::PROTOCOL_ERROR, reason)
}

fn size_err(reason: &str) -> H2Error {
    H2Error::connection(error_code::FRAME_SIZE_ERROR, reason)
}

/// Parse one frame from the front of `buf`. Returns `Ok(None)` when more bytes
/// are needed and otherwise the frame and the number of bytes it occupied. A
/// declared length above `max_frame_size` fails as soon as the header is seen.
pub fn parse_frame(buf: &[u8], max_frame_size: u32) -> Result<Option<(Frame, usize)>, H2Error> {
    if buf.len() < FRAME_HEADER_LEN {
        return Ok(None);
    }
    let len = u32::from_be_bytes([0, buf[0], buf[1], buf[2]]);
    if len > max_frame_size {
        return Err(size_err("frame exceeds SETTINGS_MAX_FRAME_SIZE"));
    }
    let total = FRAME_HEADER_LEN + len as usize;
    if buf.len() < total {
        return Ok(None);
    }
    let (ty, flags) = (buf[3], buf[4]);
    let id = u32::from_be_bytes([buf[5], buf[6], buf[7], buf[8]]) & 0x7fff_ffff;
    let frame = decode_payload(ty, flags, id, &buf[FRAME_HEADER_LEN..total])?;
    Ok(Some((frame, total)))
}

fn decode_payload(ty: u8, flags: u8, id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    match ty {
        TYPE_DATA => parse_data(flags, id, payload),
        TYPE_HEADERS => parse_headers(flags, id, payload),
        TYPE_PRIORITY => parse_priority(id, payload),
        TYPE_RST_STREAM => parse_rst(id, payload),
        TYPE_SETTINGS => parse_settings(flags, id, payload),
        TYPE_PUSH_PROMISE => parse_push_promise(flags, id, payload),
        TYPE_PING => parse_ping(flags, id, payload),
        TYPE_GOAWAY => parse_goaway(id, payload),
        TYPE_WINDOW_UPDATE => parse_window_update(id, payload),
        TYPE_CONTINUATION => parse_continuation(flags, id, payload),
        _ => Ok(Frame::Unknown { ty }),
    }
}

/// Strip the pad-length octet and trailing padding. Returns the inner payload
/// and the total padding octets (pad length + 1) or 0 when not padded.
fn strip_padding(flags: u8, payload: &[u8]) -> Result<(&[u8], u32), H2Error> {
    if flags & FLAG_PADDED == 0 {
        return Ok((payload, 0));
    }
    let Some((&pad_len, rest)) = payload.split_first() else {
        return Err(size_err("padded frame without pad length"));
    };
    if pad_len as usize >= payload.len() {
        return Err(proto("padding exceeds frame payload"));
    }
    Ok((&rest[..rest.len() - pad_len as usize], pad_len as u32 + 1))
}

fn parse_data(flags: u8, id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id == 0 {
        return Err(proto("DATA on stream 0"));
    }
    let (data, pad) = strip_padding(flags, payload)?;
    Ok(Frame::Data {
        id,
        data: data.to_vec(),
        pad,
        flow_len: payload.len() as u32,
        end_stream: flags & FLAG_END_STREAM != 0,
    })
}

fn parse_headers(flags: u8, id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id == 0 {
        return Err(proto("HEADERS on stream 0"));
    }
    let (mut block, _) = strip_padding(flags, payload)?;
    if flags & FLAG_PRIORITY != 0 {
        if block.len() < 5 {
            return Err(size_err("HEADERS priority fields truncated"));
        }
        block = &block[5..];
    }
    Ok(Frame::Headers {
        id,
        block: block.to_vec(),
        end_stream: flags & FLAG_END_STREAM != 0,
        end_headers: flags & FLAG_END_HEADERS != 0,
    })
}

fn parse_priority(id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id == 0 {
        return Err(proto("PRIORITY on stream 0"));
    }
    if payload.len() != 5 {
        return Err(size_err("PRIORITY must be 5 octets"));
    }
    Ok(Frame::Priority { id })
}

fn parse_rst(id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id == 0 {
        return Err(proto("RST_STREAM on stream 0"));
    }
    let Ok(code) = <[u8; 4]>::try_from(payload) else {
        return Err(size_err("RST_STREAM must be 4 octets"));
    };
    Ok(Frame::RstStream {
        id,
        code: u32::from_be_bytes(code),
    })
}

fn parse_settings(flags: u8, id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id != 0 {
        return Err(proto("SETTINGS on a stream"));
    }
    let ack = flags & FLAG_ACK != 0;
    if ack && !payload.is_empty() {
        return Err(size_err("SETTINGS ack with payload"));
    }
    if !payload.len().is_multiple_of(6) {
        return Err(size_err("SETTINGS length not a multiple of 6"));
    }
    let params = payload
        .chunks_exact(6)
        .map(|c| {
            (
                u16::from_be_bytes([c[0], c[1]]),
                u32::from_be_bytes([c[2], c[3], c[4], c[5]]),
            )
        })
        .collect();
    Ok(Frame::Settings { ack, params })
}

fn parse_push_promise(flags: u8, id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id == 0 {
        return Err(proto("PUSH_PROMISE on stream 0"));
    }
    let (inner, _) = strip_padding(flags, payload)?;
    let Some(p) = inner.first_chunk::<4>() else {
        return Err(size_err("PUSH_PROMISE truncated"));
    };
    Ok(Frame::PushPromise {
        id,
        promised: u32::from_be_bytes(*p) & 0x7fff_ffff,
    })
}

fn parse_ping(flags: u8, id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id != 0 {
        return Err(proto("PING on a stream"));
    }
    let Ok(data) = <[u8; 8]>::try_from(payload) else {
        return Err(size_err("PING must be 8 octets"));
    };
    Ok(Frame::Ping {
        ack: flags & FLAG_ACK != 0,
        data,
    })
}

fn parse_goaway(id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id != 0 {
        return Err(proto("GOAWAY on a stream"));
    }
    if payload.len() < 8 {
        return Err(size_err("GOAWAY shorter than 8 octets"));
    }
    Ok(Frame::GoAway {
        last_stream_id: u32::from_be_bytes([payload[0], payload[1], payload[2], payload[3]])
            & 0x7fff_ffff,
        code: u32::from_be_bytes([payload[4], payload[5], payload[6], payload[7]]),
        debug: payload[8..].to_vec(),
    })
}

fn parse_window_update(id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    let Ok(inc) = <[u8; 4]>::try_from(payload) else {
        return Err(size_err("WINDOW_UPDATE must be 4 octets"));
    };
    Ok(Frame::WindowUpdate {
        id,
        increment: u32::from_be_bytes(inc) & 0x7fff_ffff,
    })
}

fn parse_continuation(flags: u8, id: u32, payload: &[u8]) -> Result<Frame, H2Error> {
    if id == 0 {
        return Err(proto("CONTINUATION on stream 0"));
    }
    Ok(Frame::Continuation {
        id,
        block: payload.to_vec(),
        end_headers: flags & FLAG_END_HEADERS != 0,
    })
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

/// Append a frame header.
pub fn write_frame_header(out: &mut Vec<u8>, len: usize, ty: u8, flags: u8, id: u32) {
    let len = len as u32;
    out.extend_from_slice(&len.to_be_bytes()[1..]);
    out.push(ty);
    out.push(flags);
    out.extend_from_slice(&(id & 0x7fff_ffff).to_be_bytes());
}

/// Append one DATA frame; the caller keeps `data` within the peer's frame size.
pub fn write_data(out: &mut Vec<u8>, id: u32, data: &[u8], end_stream: bool) {
    let flags = if end_stream { FLAG_END_STREAM } else { 0 };
    write_frame_header(out, data.len(), TYPE_DATA, flags, id);
    out.extend_from_slice(data);
}

/// Append a HEADERS frame followed by CONTINUATION frames as needed so no frame
/// exceeds `max_frame_size`.
pub fn write_header_block(
    out: &mut Vec<u8>,
    id: u32,
    block: &[u8],
    end_stream: bool,
    max_frame_size: u32,
) {
    let max = max_frame_size as usize;
    let mut chunks = block.chunks(max).peekable();
    let first = chunks.next().unwrap_or(&[]);
    let mut flags = if end_stream { FLAG_END_STREAM } else { 0 };
    if chunks.peek().is_none() {
        flags |= FLAG_END_HEADERS;
    }
    write_frame_header(out, first.len(), TYPE_HEADERS, flags, id);
    out.extend_from_slice(first);
    while let Some(chunk) = chunks.next() {
        let flags = if chunks.peek().is_none() {
            FLAG_END_HEADERS
        } else {
            0
        };
        write_frame_header(out, chunk.len(), TYPE_CONTINUATION, flags, id);
        out.extend_from_slice(chunk);
    }
}

pub fn write_rst_stream(out: &mut Vec<u8>, id: u32, code: u32) {
    write_frame_header(out, 4, TYPE_RST_STREAM, 0, id);
    out.extend_from_slice(&code.to_be_bytes());
}

pub fn write_settings(out: &mut Vec<u8>, params: &[(u16, u32)]) {
    write_frame_header(out, params.len() * 6, TYPE_SETTINGS, 0, 0);
    for &(k, v) in params {
        out.extend_from_slice(&k.to_be_bytes());
        out.extend_from_slice(&v.to_be_bytes());
    }
}

pub fn write_settings_ack(out: &mut Vec<u8>) {
    write_frame_header(out, 0, TYPE_SETTINGS, FLAG_ACK, 0);
}

pub fn write_ping(out: &mut Vec<u8>, ack: bool, data: [u8; 8]) {
    write_frame_header(out, 8, TYPE_PING, if ack { FLAG_ACK } else { 0 }, 0);
    out.extend_from_slice(&data);
}

pub fn write_goaway(out: &mut Vec<u8>, last_stream_id: u32, code: u32, debug: &[u8]) {
    write_frame_header(out, 8 + debug.len(), TYPE_GOAWAY, 0, 0);
    out.extend_from_slice(&(last_stream_id & 0x7fff_ffff).to_be_bytes());
    out.extend_from_slice(&code.to_be_bytes());
    out.extend_from_slice(debug);
}

pub fn write_window_update(out: &mut Vec<u8>, id: u32, increment: u32) {
    write_frame_header(out, 4, TYPE_WINDOW_UPDATE, 0, id);
    out.extend_from_slice(&(increment & 0x7fff_ffff).to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(bytes: &[u8]) -> Frame {
        let (f, n) = parse_frame(bytes, DEFAULT_MAX_FRAME_SIZE).unwrap().unwrap();
        assert_eq!(n, bytes.len());
        f
    }

    fn raw(ty: u8, flags: u8, id: u32, payload: &[u8]) -> Vec<u8> {
        let mut v = Vec::new();
        write_frame_header(&mut v, payload.len(), ty, flags, id);
        v.extend_from_slice(payload);
        v
    }

    #[test]
    fn partial_input_waits() {
        let bytes = raw(TYPE_PING, 0, 0, &[1; 8]);
        for n in 0..bytes.len() {
            assert!(parse_frame(&bytes[..n], 16384).unwrap().is_none(), "n={n}");
        }
        assert!(parse_frame(&bytes, 16384).unwrap().is_some());
    }

    #[test]
    fn data_with_padding() {
        // pad length 3, "hi", 3 pad octets.
        let f = parse(&raw(
            TYPE_DATA,
            FLAG_PADDED | FLAG_END_STREAM,
            1,
            &[3, b'h', b'i', 0, 0, 0],
        ));
        assert_eq!(
            f,
            Frame::Data {
                id: 1,
                data: b"hi".to_vec(),
                pad: 4,
                flow_len: 6,
                end_stream: true
            }
        );
    }

    #[test]
    fn padding_longer_than_payload_is_protocol_error() {
        let bytes = raw(TYPE_DATA, FLAG_PADDED, 1, &[5, 1, 2]);
        let e = parse_frame(&bytes, 16384).unwrap_err();
        assert_eq!(e.code, error_code::PROTOCOL_ERROR);
        // Pad length equal to the remaining payload is also invalid.
        let bytes = raw(TYPE_DATA, FLAG_PADDED, 1, &[3, 1, 2]);
        assert!(parse_frame(&bytes, 16384).is_err());
    }

    #[test]
    fn headers_with_priority_and_padding() {
        let mut payload = vec![2u8]; // pad length
        payload.extend_from_slice(&[0x80, 0, 0, 3, 15]); // dependency + weight
        payload.extend_from_slice(&[0x82, 0x84]); // block
        payload.extend_from_slice(&[0, 0]); // padding
        let f = parse(&raw(
            TYPE_HEADERS,
            FLAG_PADDED | FLAG_PRIORITY | FLAG_END_HEADERS,
            3,
            &payload,
        ));
        assert_eq!(
            f,
            Frame::Headers {
                id: 3,
                block: vec![0x82, 0x84],
                end_stream: false,
                end_headers: true
            }
        );
    }

    #[test]
    fn priority_is_parsed_and_validated() {
        assert_eq!(
            parse(&raw(TYPE_PRIORITY, 0, 5, &[0, 0, 0, 1, 9])),
            Frame::Priority { id: 5 }
        );
        assert!(parse_frame(&raw(TYPE_PRIORITY, 0, 5, &[0; 4]), 16384).is_err());
        assert!(parse_frame(&raw(TYPE_PRIORITY, 0, 0, &[0; 5]), 16384).is_err());
    }

    #[test]
    fn settings_roundtrip_and_errors() {
        let mut out = Vec::new();
        write_settings(&mut out, &[(SETTINGS_INITIAL_WINDOW_SIZE, 1000), (3, 7)]);
        assert_eq!(
            parse(&out),
            Frame::Settings {
                ack: false,
                params: vec![(4, 1000), (3, 7)]
            }
        );
        let mut ack = Vec::new();
        write_settings_ack(&mut ack);
        assert_eq!(
            parse(&ack),
            Frame::Settings {
                ack: true,
                params: vec![]
            }
        );
        let bad = raw(TYPE_SETTINGS, 0, 0, &[0; 5]);
        assert_eq!(
            parse_frame(&bad, 16384).unwrap_err().code,
            error_code::FRAME_SIZE_ERROR
        );
        let bad = raw(TYPE_SETTINGS, FLAG_ACK, 0, &[0; 6]);
        assert!(parse_frame(&bad, 16384).is_err());
        let bad = raw(TYPE_SETTINGS, 0, 1, &[]);
        assert_eq!(
            parse_frame(&bad, 16384).unwrap_err().code,
            error_code::PROTOCOL_ERROR
        );
    }

    #[test]
    fn ping_goaway_window_update_rst() {
        let mut out = Vec::new();
        write_ping(&mut out, true, *b"12345678");
        assert_eq!(
            parse(&out),
            Frame::Ping {
                ack: true,
                data: *b"12345678"
            }
        );
        out.clear();
        write_goaway(&mut out, 7, error_code::ENHANCE_YOUR_CALM, b"bye");
        assert_eq!(
            parse(&out),
            Frame::GoAway {
                last_stream_id: 7,
                code: error_code::ENHANCE_YOUR_CALM,
                debug: b"bye".to_vec()
            }
        );
        out.clear();
        write_window_update(&mut out, 9, 0x7fff_ffff);
        assert_eq!(
            parse(&out),
            Frame::WindowUpdate {
                id: 9,
                increment: 0x7fff_ffff
            }
        );
        out.clear();
        write_rst_stream(&mut out, 9, error_code::CANCEL);
        assert_eq!(
            parse(&out),
            Frame::RstStream {
                id: 9,
                code: error_code::CANCEL
            }
        );
        assert!(parse_frame(&raw(TYPE_PING, 0, 1, &[0; 8]), 16384).is_err());
        assert!(parse_frame(&raw(TYPE_PING, 0, 0, &[0; 7]), 16384).is_err());
        assert!(parse_frame(&raw(TYPE_GOAWAY, 0, 0, &[0; 7]), 16384).is_err());
        assert!(parse_frame(&raw(TYPE_WINDOW_UPDATE, 0, 0, &[0; 3]), 16384).is_err());
    }

    #[test]
    fn reserved_bit_is_masked() {
        let mut bytes = raw(TYPE_RST_STREAM, 0, 1, &[0, 0, 0, 8]);
        bytes[5] |= 0x80;
        assert_eq!(
            parse(&bytes),
            Frame::RstStream {
                id: 1,
                code: error_code::CANCEL
            }
        );
    }

    #[test]
    fn unknown_type_is_surfaced_for_skipping() {
        assert_eq!(parse(&raw(0xee, 0, 1, b"xyz")), Frame::Unknown { ty: 0xee });
    }

    #[test]
    fn oversize_frame_fails_on_header_alone() {
        let mut header = Vec::new();
        write_frame_header(&mut header, 16385, TYPE_DATA, 0, 1);
        let e = parse_frame(&header, 16384).unwrap_err();
        assert_eq!(e.code, error_code::FRAME_SIZE_ERROR);
        // A raised limit accepts it (and waits for the payload).
        assert!(parse_frame(&header, 1 << 16).unwrap().is_none());
    }

    #[test]
    fn header_block_splits_into_continuations() {
        let block = vec![0x82u8; 25];
        let mut out = Vec::new();
        write_header_block(&mut out, 1, &block, true, 10);
        let mut pos = 0;
        let mut frames = Vec::new();
        while pos < out.len() {
            let (f, n) = parse_frame(&out[pos..], 10).unwrap().unwrap();
            pos += n;
            frames.push(f);
        }
        assert_eq!(frames.len(), 3);
        assert_eq!(
            frames[0],
            Frame::Headers {
                id: 1,
                block: vec![0x82; 10],
                end_stream: true,
                end_headers: false
            }
        );
        assert_eq!(
            frames[1],
            Frame::Continuation {
                id: 1,
                block: vec![0x82; 10],
                end_headers: false
            }
        );
        assert_eq!(
            frames[2],
            Frame::Continuation {
                id: 1,
                block: vec![0x82; 5],
                end_headers: true
            }
        );
    }

    #[test]
    fn empty_header_block_is_one_frame() {
        let mut out = Vec::new();
        write_header_block(&mut out, 3, &[], false, 16384);
        assert_eq!(
            parse(&out),
            Frame::Headers {
                id: 3,
                block: vec![],
                end_stream: false,
                end_headers: true
            }
        );
    }
}
