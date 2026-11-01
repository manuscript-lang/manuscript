//! HTTP/1.1 wire format: heads, body framing, chunked coding.
//!
//! Everything here works on byte buffers and never touches a socket.

use std::io::Write as _;

/// Longest request or status line plus headers when no limit is configured.
pub const DEFAULT_HEAD_LIMIT: usize = 1 << 20;

/// Why a message head or body was refused, with the status a server answers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BadMessage {
    pub status: u16,
    pub reason: &'static str,
}

impl BadMessage {
    pub const fn new(status: u16, reason: &'static str) -> BadMessage {
        BadMessage { status, reason }
    }
}

/// A parsed request head.
#[derive(Clone, Debug)]
pub struct RequestHead {
    pub method: String,
    pub target: String,
    /// Minor HTTP version (0 or 1).
    pub minor: u8,
    pub fields: Vec<(String, Vec<u8>)>,
    /// Bytes of the head, including the blank line.
    pub length: usize,
}

/// A parsed response head.
#[derive(Clone, Debug)]
pub struct ResponseHead {
    pub status: u16,
    pub minor: u8,
    pub fields: Vec<(String, Vec<u8>)>,
    pub length: usize,
}

pub enum Parsed<T> {
    Partial,
    Complete(T),
    Bad(BadMessage),
}

/// Most header fields a message may carry before it is refused.
pub const MAX_FIELDS: usize = 256;

fn collect(headers: &[httparse::Header<'_>]) -> Vec<(String, Vec<u8>)> {
    headers
        .iter()
        .map(|h| (h.name.to_string(), h.value.to_vec()))
        .collect()
}

/// Whether every CR and LF of a head is part of a CRLF pair; a bare one lets two parsers split
/// the message differently.
fn strict_line_endings(head: &[u8]) -> bool {
    head.iter().enumerate().all(|(i, &c)| match c {
        b'\n' => i > 0 && head[i - 1] == b'\r',
        b'\r' => head.get(i + 1) == Some(&b'\n'),
        _ => true,
    })
}

/// Parses a request head from the front of `buf`.
pub fn parse_request(buf: &[u8], limit: usize) -> Parsed<RequestHead> {
    let mut storage = [httparse::EMPTY_HEADER; MAX_FIELDS];
    let mut req = httparse::Request::new(&mut storage);
    match req.parse(buf) {
        Ok(httparse::Status::Complete(length)) => {
            if length > limit {
                return Parsed::Bad(BadMessage::new(431, "Request Header Fields Too Large"));
            }
            if !strict_line_endings(&buf[..length]) {
                return Parsed::Bad(BadMessage::new(400, "Bad Request"));
            }
            Parsed::Complete(RequestHead {
                method: req.method.unwrap_or_default().to_string(),
                target: req.path.unwrap_or_default().to_string(),
                minor: req.version.unwrap_or(1),
                fields: collect(req.headers),
                length,
            })
        }
        Ok(httparse::Status::Partial) => {
            if buf.len() > limit {
                Parsed::Bad(BadMessage::new(431, "Request Header Fields Too Large"))
            } else {
                Parsed::Partial
            }
        }
        Err(httparse::Error::TooManyHeaders) => {
            Parsed::Bad(BadMessage::new(431, "Request Header Fields Too Large"))
        }
        Err(httparse::Error::Version) => {
            Parsed::Bad(BadMessage::new(505, "HTTP Version Not Supported"))
        }
        Err(_) => Parsed::Bad(BadMessage::new(400, "Bad Request")),
    }
}

/// Parses a response head from the front of `buf`.
pub fn parse_response(buf: &[u8], limit: usize) -> Parsed<ResponseHead> {
    let mut storage = [httparse::EMPTY_HEADER; MAX_FIELDS];
    let mut res = httparse::Response::new(&mut storage);
    match res.parse(buf) {
        Ok(httparse::Status::Complete(length)) => {
            if length > limit {
                return Parsed::Bad(BadMessage::new(0, "response headers too large"));
            }
            Parsed::Complete(ResponseHead {
                status: res.code.unwrap_or(0),
                minor: res.version.unwrap_or(1),
                fields: collect(res.headers),
                length,
            })
        }
        Ok(httparse::Status::Partial) => {
            if buf.len() > limit {
                Parsed::Bad(BadMessage::new(0, "response headers too large"))
            } else {
                Parsed::Partial
            }
        }
        Err(httparse::Error::TooManyHeaders) => {
            Parsed::Bad(BadMessage::new(0, "too many response header fields"))
        }
        Err(_) => Parsed::Bad(BadMessage::new(0, "malformed HTTP response")),
    }
}

/// How the body of a message is delimited.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Framing {
    None,
    Length(u64),
    Chunked,
    /// Responses only: the body ends when the connection closes.
    UntilClose,
}

fn field<'a>(fields: &'a [(String, Vec<u8>)], name: &str) -> impl Iterator<Item = &'a [u8]> {
    fields
        .iter()
        .filter(move |(n, _)| n.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_slice())
}

/// Whether a comma-separated field holds `token` (case-insensitive).
pub fn has_token(fields: &[(String, Vec<u8>)], name: &str, token: &str) -> bool {
    field(fields, name).any(|v| {
        v.split(|&c| c == b',')
            .any(|t| t.trim_ascii().eq_ignore_ascii_case(token.as_bytes()))
    })
}

fn content_length(fields: &[(String, Vec<u8>)]) -> Result<Option<u64>, ()> {
    let mut found: Option<u64> = None;
    for value in field(fields, "Content-Length") {
        for part in value.split(|&c| c == b',') {
            let part = part.trim_ascii();
            if part.is_empty() || !part.iter().all(u8::is_ascii_digit) {
                return Err(());
            }
            let n: u64 = std::str::from_utf8(part)
                .ok()
                .and_then(|s| s.parse().ok())
                .ok_or(())?;
            if found.is_some_and(|f| f != n) {
                return Err(());
            }
            found = Some(n);
        }
    }
    Ok(found)
}

/// Request body framing as the server reads it; a message with both `Transfer-Encoding` and
/// `Content-Length` is refused.
pub fn request_framing(head: &RequestHead) -> Result<Framing, BadMessage> {
    let bad_length = BadMessage::new(400, "Bad Request");
    let encodings: Vec<&[u8]> = field(&head.fields, "Transfer-Encoding").collect();
    if !encodings.is_empty() {
        let list: Vec<&[u8]> = encodings
            .iter()
            .flat_map(|v| v.split(|&c| c == b','))
            .map(<[u8]>::trim_ascii)
            .filter(|t| !t.is_empty())
            .collect();
        // Both framings make the request's end ambiguous between parsers: refuse it.
        if head.minor == 0 || field(&head.fields, "Content-Length").next().is_some() {
            return Err(bad_length);
        }
        return match list.as_slice() {
            [t] if t.eq_ignore_ascii_case(b"chunked") => Ok(Framing::Chunked),
            _ => Err(BadMessage::new(501, "Not Implemented")),
        };
    }
    match content_length(&head.fields) {
        Err(()) => Err(bad_length),
        Ok(Some(0)) | Ok(None) => Ok(Framing::None),
        Ok(Some(n)) => Ok(Framing::Length(n)),
    }
}

/// Response body framing for a request made with `method`.
pub fn response_framing(head: &ResponseHead, method: &str) -> Result<Framing, &'static str> {
    if method == "HEAD"
        || (100..200).contains(&head.status)
        || head.status == 204
        || head.status == 304
    {
        return Ok(Framing::None);
    }
    if has_token(&head.fields, "Transfer-Encoding", "chunked") {
        // Another coding would hand the caller still-encoded bytes as the body.
        let coded = field(&head.fields, "Transfer-Encoding").any(|v| {
            v.split(|&c| c == b',').map(<[u8]>::trim_ascii).any(|t| {
                !t.eq_ignore_ascii_case(b"chunked") && !t.eq_ignore_ascii_case(b"identity")
            })
        });
        if coded {
            return Err("unsupported Transfer-Encoding");
        }
        return Ok(Framing::Chunked);
    }
    if field(&head.fields, "Transfer-Encoding").next().is_some() {
        return Ok(Framing::UntilClose);
    }
    match content_length(&head.fields) {
        Err(()) => Err("invalid Content-Length"),
        Ok(Some(n)) => Ok(Framing::Length(n)),
        Ok(None) => Ok(Framing::UntilClose),
    }
}

/// Whether the connection stays open after this message.
pub fn keep_alive(minor: u8, fields: &[(String, Vec<u8>)]) -> bool {
    if has_token(fields, "Connection", "close") {
        return false;
    }
    minor >= 1 || has_token(fields, "Connection", "keep-alive")
}

/// Progress of an incremental body decode.
#[derive(Debug, PartialEq, Eq)]
pub enum Decoded {
    /// Input exhausted; more is needed.
    More,
    /// The body is complete; trailing input stays with the caller.
    Done,
}

#[derive(Debug)]
enum State {
    Length(u64),
    Size,
    Data(u64),
    DataEnd,
    Trailer,
    Done,
    UntilClose,
}

/// Incremental body decoder.
#[derive(Debug)]
pub struct BodyDecoder {
    state: State,
    size: Vec<u8>,
    trailer_line: usize,
    /// A CR was read and its LF is due: the end of chunk data or of a trailer line.
    cr: bool,
}

impl BodyDecoder {
    pub fn new(framing: Framing) -> BodyDecoder {
        let state = match framing {
            Framing::None => State::Done,
            Framing::Length(0) => State::Done,
            Framing::Length(n) => State::Length(n),
            Framing::Chunked => State::Size,
            Framing::UntilClose => State::UntilClose,
        };
        BodyDecoder {
            state,
            size: Vec::new(),
            trailer_line: 0,
            cr: false,
        }
    }

    pub fn is_done(&self) -> bool {
        matches!(self.state, State::Done)
    }

    /// How many body bytes the next read may take when they are raw (a fixed length, the data
    /// of one chunk, or until close), so they can bypass `feed`; `None` between chunks and
    /// once the body is finished.
    pub fn raw_room(&self) -> Option<u64> {
        match self.state {
            State::Length(left) | State::Data(left) => Some(left),
            State::UntilClose => Some(u64::MAX),
            _ => None,
        }
    }

    /// Whether the raw bytes ahead are the whole rest of the body, so its size is known.
    pub fn is_fixed_length(&self) -> bool {
        matches!(self.state, State::Length(_))
    }

    /// Accounts for `n` raw body bytes taken without `feed` (see `raw_room`).
    pub fn took_raw(&mut self, n: usize) -> Decoded {
        match &mut self.state {
            State::Length(left) => {
                *left -= n as u64;
                if *left == 0 {
                    self.state = State::Done;
                    return Decoded::Done;
                }
            }
            State::Data(left) => {
                *left -= n as u64;
                if *left == 0 {
                    self.state = State::DataEnd;
                }
            }
            _ => {}
        }
        Decoded::More
    }

    /// Consumes input, appending body bytes to `out`; returns bytes consumed and
    /// the progress. A malformed chunked body is an `Err`.
    pub fn feed(
        &mut self,
        input: &[u8],
        out: &mut Vec<u8>,
    ) -> Result<(usize, Decoded), &'static str> {
        let mut at = 0;
        loop {
            match &mut self.state {
                State::Done => return Ok((at, Decoded::Done)),
                State::UntilClose => {
                    out.extend_from_slice(&input[at..]);
                    return Ok((input.len(), Decoded::More));
                }
                State::Length(left) => {
                    let n = ((input.len() - at) as u64).min(*left) as usize;
                    out.extend_from_slice(&input[at..at + n]);
                    at += n;
                    *left -= n as u64;
                    if *left == 0 {
                        self.state = State::Done;
                        return Ok((at, Decoded::Done));
                    }
                    return Ok((at, Decoded::More));
                }
                State::Size => {
                    let Some(rel) = input[at..].iter().position(|&c| c == b'\n') else {
                        self.size.extend_from_slice(&input[at..]);
                        if self.size.len() > 4096 {
                            return Err("chunk size line too long");
                        }
                        return Ok((input.len(), Decoded::More));
                    };
                    self.size.extend_from_slice(&input[at..at + rel]);
                    if self.size.len() > 4096 {
                        return Err("chunk size line too long");
                    }
                    at += rel + 1;
                    let line = std::mem::take(&mut self.size);
                    let Some(line) = line.strip_suffix(b"\r") else {
                        return Err("chunk size line must end with CRLF");
                    };
                    let digits: &[u8] = line.split(|&c| c == b';').next().unwrap_or(&[]);
                    let digits = digits.trim_ascii();
                    if digits.is_empty()
                        || !digits.iter().all(u8::is_ascii_hexdigit)
                        || digits.len() > 16
                    {
                        return Err("invalid chunk size");
                    }
                    let n = u64::from_str_radix(std::str::from_utf8(digits).unwrap_or("x"), 16)
                        .map_err(|_| "invalid chunk size")?;
                    self.state = if n == 0 {
                        State::Trailer
                    } else {
                        State::Data(n)
                    };
                    self.trailer_line = 0;
                }
                State::Data(left) => {
                    if at == input.len() {
                        return Ok((at, Decoded::More));
                    }
                    let n = ((input.len() - at) as u64).min(*left) as usize;
                    out.extend_from_slice(&input[at..at + n]);
                    at += n;
                    *left -= n as u64;
                    if *left == 0 {
                        self.state = State::DataEnd;
                    }
                }
                State::DataEnd => {
                    // The CRLF after chunk data, possibly split across reads.
                    while at < input.len() {
                        let c = input[at];
                        at += 1;
                        match (c, self.cr) {
                            (b'\r', false) => self.cr = true,
                            (b'\n', true) => {
                                self.cr = false;
                                self.state = State::Size;
                                break;
                            }
                            _ => return Err("malformed chunk terminator"),
                        }
                    }
                    if matches!(self.state, State::DataEnd) {
                        return Ok((at, Decoded::More));
                    }
                }
                State::Trailer => {
                    // Skip trailer lines until the empty line.
                    while at < input.len() {
                        let c = input[at];
                        at += 1;
                        match c {
                            b'\n' => {
                                if !self.cr {
                                    return Err("trailer line must end with CRLF");
                                }
                                self.cr = false;
                                if self.trailer_line == 0 {
                                    self.state = State::Done;
                                    return Ok((at, Decoded::Done));
                                }
                                self.trailer_line = 0;
                            }
                            _ if self.cr => return Err("bare CR in trailer"),
                            b'\r' => self.cr = true,
                            _ => {
                                self.trailer_line += 1;
                                if self.trailer_line > 8192 {
                                    return Err("trailer too long");
                                }
                            }
                        }
                    }
                    return Ok((at, Decoded::More));
                }
            }
        }
    }

    /// Whether end of input completes the body (read until close).
    pub fn finish_on_eof(&self) -> bool {
        matches!(self.state, State::UntilClose | State::Done)
    }
}

/// `http.StatusText`.
pub fn status_text(code: u16) -> &'static str {
    match code {
        100 => "Continue",
        101 => "Switching Protocols",
        102 => "Processing",
        103 => "Early Hints",
        200 => "OK",
        201 => "Created",
        202 => "Accepted",
        203 => "Non-Authoritative Information",
        204 => "No Content",
        205 => "Reset Content",
        206 => "Partial Content",
        207 => "Multi-Status",
        208 => "Already Reported",
        226 => "IM Used",
        300 => "Multiple Choices",
        301 => "Moved Permanently",
        302 => "Found",
        303 => "See Other",
        304 => "Not Modified",
        305 => "Use Proxy",
        307 => "Temporary Redirect",
        308 => "Permanent Redirect",
        400 => "Bad Request",
        401 => "Unauthorized",
        402 => "Payment Required",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        406 => "Not Acceptable",
        407 => "Proxy Authentication Required",
        408 => "Request Timeout",
        409 => "Conflict",
        410 => "Gone",
        411 => "Length Required",
        412 => "Precondition Failed",
        413 => "Request Entity Too Large",
        414 => "Request URI Too Long",
        415 => "Unsupported Media Type",
        416 => "Requested Range Not Satisfiable",
        417 => "Expectation Failed",
        418 => "I'm a teapot",
        421 => "Misdirected Request",
        422 => "Unprocessable Entity",
        423 => "Locked",
        424 => "Failed Dependency",
        425 => "Too Early",
        426 => "Upgrade Required",
        428 => "Precondition Required",
        429 => "Too Many Requests",
        431 => "Request Header Fields Too Large",
        451 => "Unavailable For Legal Reasons",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        505 => "HTTP Version Not Supported",
        506 => "Variant Also Negotiates",
        507 => "Insufficient Storage",
        508 => "Loop Detected",
        510 => "Not Extended",
        511 => "Network Authentication Required",
        _ => "",
    }
}

/// Appends the status line, `HTTP/1.1 200 OK\r\n`.
pub fn status_line(out: &mut Vec<u8>, status: u16) {
    let text = status_text(status);
    if (100..1000).contains(&status) && !text.is_empty() {
        out.extend_from_slice(b"HTTP/1.1 ");
        out.extend_from_slice(&[
            b'0' + (status / 100) as u8,
            b'0' + (status / 10 % 10) as u8,
            b'0' + (status % 10) as u8,
            b' ',
        ]);
        out.extend_from_slice(text.as_bytes());
        out.extend_from_slice(b"\r\n");
    } else if text.is_empty() {
        let _ = write!(out, "HTTP/1.1 {status} status code {status}\r\n");
    } else {
        let _ = write!(out, "HTTP/1.1 {status} {text}\r\n");
    }
}

/// Appends `name: value\r\n`.
pub fn header_line(out: &mut Vec<u8>, name: &str, value: &[u8]) {
    out.extend_from_slice(name.as_bytes());
    out.extend_from_slice(b": ");
    out.extend_from_slice(value);
    out.extend_from_slice(b"\r\n");
}

/// Appends `name: <n>\r\n`.
pub fn header_number(out: &mut Vec<u8>, name: &str, n: usize) {
    let mut digits = [0u8; 20];
    let mut at = digits.len();
    let mut rest = n;
    loop {
        at -= 1;
        digits[at] = b'0' + (rest % 10) as u8;
        rest /= 10;
        if rest == 0 {
            break;
        }
    }
    header_line(out, name, &digits[at..]);
}

/// Appends one chunk.
pub fn chunk(out: &mut Vec<u8>, data: &[u8]) {
    if data.is_empty() {
        return;
    }
    let _ = write!(out, "{:x}\r\n", data.len());
    out.extend_from_slice(data);
    out.extend_from_slice(b"\r\n");
}

/// The terminating chunk.
pub const LAST_CHUNK: &[u8] = b"0\r\n\r\n";

/// `Date` header value in the format of `http.TimeFormat`.
pub fn http_date(unix_seconds: i64) -> String {
    const DAYS: [&str; 7] = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"];
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let days = unix_seconds.div_euclid(86_400);
    let secs = unix_seconds.rem_euclid(86_400);
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{}, {:02} {} {} {:02}:{:02}:{:02} GMT",
        DAYS[days.rem_euclid(7) as usize],
        day,
        MONTHS[(month - 1) as usize],
        year,
        secs / 3600,
        secs % 3600 / 60,
        secs % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(text: &str) -> RequestHead {
        match parse_request(text.as_bytes(), DEFAULT_HEAD_LIMIT) {
            Parsed::Complete(h) => h,
            Parsed::Partial => panic!("partial"),
            Parsed::Bad(b) => panic!("{b:?}"),
        }
    }

    #[test]
    fn parses_request_heads() {
        let h = request("GET /a?b=1 HTTP/1.1\r\nHost: x\r\nX-A: 1\r\n\r\nBODY");
        assert_eq!(h.method, "GET");
        assert_eq!(h.target, "/a?b=1");
        assert_eq!(h.minor, 1);
        assert_eq!(h.fields.len(), 2);
        assert_eq!(
            h.length,
            "GET /a?b=1 HTTP/1.1\r\nHost: x\r\nX-A: 1\r\n\r\n".len()
        );
        assert!(matches!(parse_request(b"GET / HTT", 100), Parsed::Partial));
        assert!(matches!(
            parse_request(b"GET / HTTP/1.1\r\nBad Header\r\n\r\n", 100),
            Parsed::Bad(BadMessage { status: 400, .. })
        ));
        assert!(matches!(
            parse_request(b"GET / HTTP/1.1\r\nA: bbbbbbbbbbbbbbbbbbbbbbbb", 20),
            Parsed::Bad(BadMessage { status: 431, .. })
        ));
    }

    #[test]
    fn request_framing_rules() {
        let f = |t: &str| request_framing(&request(t));
        assert_eq!(
            f("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\n"),
            Ok(Framing::Length(5))
        );
        assert_eq!(
            f("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n")
                .unwrap_err()
                .status,
            400
        );
        assert_eq!(
            f("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"),
            Ok(Framing::Chunked)
        );
        assert_eq!(f("GET / HTTP/1.1\r\n\r\n"), Ok(Framing::None));
        assert!(f("POST / HTTP/1.1\r\nContent-Length: x\r\n\r\n").is_err());
        assert!(f("POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n").is_err());
        assert_eq!(
            f("POST / HTTP/1.1\r\nTransfer-Encoding: gzip, chunked\r\n\r\n")
                .unwrap_err()
                .status,
            501
        );
    }

    #[test]
    fn chunked_decoding_across_splits() {
        let wire = b"5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\nTrail: x\r\n\r\nNEXT";
        for split in 1..wire.len() {
            let mut d = BodyDecoder::new(Framing::Chunked);
            let mut out = Vec::new();
            let (a, state) = d.feed(&wire[..split], &mut out).unwrap();
            assert_eq!(a, split.min(a));
            let mut consumed = a;
            if state == Decoded::More {
                let (b, s2) = d.feed(&wire[split..], &mut out).unwrap();
                assert_eq!(s2, Decoded::Done, "split {split}");
                consumed += b;
            }
            assert_eq!(out, b"hello world", "split {split}");
            assert_eq!(&wire[consumed..], b"NEXT", "split {split}");
        }
        let mut d = BodyDecoder::new(Framing::Chunked);
        assert!(d.feed(b"zz\r\n", &mut Vec::new()).is_err());
    }

    #[test]
    fn chunk_size_line_limit_does_not_depend_on_read_splits() {
        // The limit includes the CR before LF, as in an incomplete size line.
        for extension in [4093, 4094, 4095, 8192] {
            let wire = format!("1;{}\r\nx\r\n0\r\n\r\n", "a".repeat(extension));
            for split in [0, 1, 4096, 4097, wire.len()] {
                let mut decoder = BodyDecoder::new(Framing::Chunked);
                let mut body = Vec::new();
                let result = decoder
                    .feed(&wire.as_bytes()[..split], &mut body)
                    .and_then(|_| decoder.feed(&wire.as_bytes()[split..], &mut body));
                assert_eq!(
                    result.is_ok(),
                    extension <= 4093,
                    "extension={extension}, split={split}"
                );
                if result.is_ok() {
                    assert_eq!(body, b"x");
                    assert!(decoder.is_done());
                }
            }
        }
    }

    #[test]
    fn chunked_decoding_requires_crlf() {
        for wire in [
            &b"3\nabc\r\n0\r\n\r\n"[..],
            b"3\r\nabc\n0\r\n\r\n",
            b"3\r\nabc\r\r\n0\r\n\r\n",
            b"3\r\nabcX\r\n0\r\n\r\n",
            b"3\r\nabc\r\n0\r\nT: x\n\r\n",
            b"3\r\nabc\r\n0\r\nT: x\r\r\n\r\n",
            b"3\r\nabc\r\n0\n\n",
        ] {
            let mut d = BodyDecoder::new(Framing::Chunked);
            assert!(d.feed(wire, &mut Vec::new()).is_err(), "{wire:?}");
        }
    }

    #[test]
    fn heads_with_bare_line_endings_are_refused() {
        for wire in [
            &b"GET / HTTP/1.1\nHost: x\n\n"[..],
            b"GET / HTTP/1.1\r\nHost: x\n\r\n",
            b"GET / HTTP/1.1\r\nHost: x\r\n\n",
        ] {
            assert!(
                matches!(parse_request(wire, 1000), Parsed::Bad(b) if b.status == 400),
                "{wire:?}"
            );
        }
    }

    #[test]
    fn length_decoding_and_keep_alive() {
        let mut d = BodyDecoder::new(Framing::Length(4));
        let mut out = Vec::new();
        assert_eq!(d.feed(b"ab", &mut out).unwrap(), (2, Decoded::More));
        assert_eq!(d.feed(b"cdXX", &mut out).unwrap(), (2, Decoded::Done));
        assert_eq!(out, b"abcd");
        let h = request("GET / HTTP/1.0\r\n\r\n");
        assert!(!keep_alive(h.minor, &h.fields));
        let h = request("GET / HTTP/1.1\r\nConnection: close\r\n\r\n");
        assert!(!keep_alive(h.minor, &h.fields));
        let h = request("GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n");
        assert!(keep_alive(h.minor, &h.fields));
    }

    #[test]
    fn response_framing_rules() {
        let parse = |t: &str| match parse_response(t.as_bytes(), DEFAULT_HEAD_LIMIT) {
            Parsed::Complete(h) => h,
            _ => panic!("bad"),
        };
        let h = parse("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n");
        assert_eq!(response_framing(&h, "GET"), Ok(Framing::Length(3)));
        assert_eq!(response_framing(&h, "HEAD"), Ok(Framing::None));
        assert_eq!(response_framing(&h, "head"), Ok(Framing::Length(3)));
        assert_eq!(response_framing(&h, "Head"), Ok(Framing::Length(3)));
        let h = parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");
        assert_eq!(response_framing(&h, "GET"), Ok(Framing::Chunked));
        let h = parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n");
        assert_eq!(
            response_framing(&h, "GET"),
            Err("unsupported Transfer-Encoding")
        );
        let h = parse("HTTP/1.1 204 No Content\r\n\r\n");
        assert_eq!(response_framing(&h, "GET"), Ok(Framing::None));
        let h = parse("HTTP/1.1 200 OK\r\n\r\n");
        assert_eq!(response_framing(&h, "GET"), Ok(Framing::UntilClose));
    }

    #[test]
    fn dates_and_lines() {
        assert_eq!(http_date(0), "Thu, 01 Jan 1970 00:00:00 GMT");
        assert_eq!(http_date(1_700_000_000), "Tue, 14 Nov 2023 22:13:20 GMT");
        assert_eq!(http_date(951_782_400), "Tue, 29 Feb 2000 00:00:00 GMT");
        let mut out = Vec::new();
        status_line(&mut out, 299);
        chunk(&mut out, b"abc");
        assert_eq!(out, b"HTTP/1.1 299 status code 299\r\n3\r\nabc\r\n");
    }
}
