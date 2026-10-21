//! `@std/json.ms` natives a strict JSON parser that
//! keeps number text verbatim and rejects duplicate keys, trailing values and unpaired surrogate
//! escapes, and a serializer.
//!
//! Values live in an arena ([`Doc`]) so that neither side needs the other's value layout: the
//! parser builds a [`Doc`], the generated typed decoders read it through node ids, and typed
//! encoders build a [`Doc`] that [`Doc::stringify`] serializes. Both walks are iterative, so
//! nesting up to the 100 000 level ceiling cannot overflow the native stack.
#![no_std]

extern crate alloc;

pub mod ffi;

use alloc::collections::BTreeSet;
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::Fail;

/// The deepest container nesting `parse` accepts.
pub const DEPTH_CEILING: usize = 100_000;
/// The widest indent `stringify` honors.
pub const INDENT_CEILING: usize = 10;

pub type NodeId = u32;

#[derive(Clone)]
pub enum Node {
    Null,
    Bool(bool),
    /// Exact number text.
    Number(String),
    Str(String),
    Array(Vec<NodeId>),
    /// Members in insertion order, keys unique.
    Object(Vec<(String, NodeId)>),
}

#[derive(Clone, Copy, Default)]
pub struct Limits {
    pub max_bytes: Option<i64>,
    pub max_depth: Option<i64>,
    pub max_values: Option<i64>,
}

#[derive(Default)]
pub struct Doc {
    pub nodes: Vec<Node>,
}

fn budget(o: Option<i64>) -> Result<usize, Fail> {
    match o {
        None => Ok(usize::MAX),
        Some(n) => usize::try_from(n).map_err(|_| Fail::InvalidInput),
    }
}

/// Rejects unpaired surrogate escapes before parsing (Go's decoder would replace them). The scan
/// follows quote parity over the whole text exactly like `jsonUnicodeValid`.
fn unicode_valid(s: &[u8]) -> bool {
    let hex4 = |at: usize| -> Option<u32> {
        let d = s.get(at..at + 4)?;
        d.iter()
            .try_fold(0u32, |acc, &c| Some(acc << 4 | char::from(c).to_digit(16)?))
    };
    let (mut in_string, mut i) = (false, 0);
    while i < s.len() {
        let c = s[i];
        if c == b'"' {
            in_string = !in_string;
        } else if in_string && c == b'\\' {
            i += 1;
            if i >= s.len() {
                return false;
            }
            if s[i] == b'u' {
                if i + 4 >= s.len() {
                    return false;
                }
                let Some(v) = hex4(i + 1) else {
                    return false;
                };
                i += 4;
                if (0xDC00..=0xDFFF).contains(&v) {
                    return false;
                }
                if (0xD800..=0xDBFF).contains(&v) {
                    if i + 6 >= s.len() || &s[i + 1..i + 3] != b"\\u" {
                        return false;
                    }
                    match hex4(i + 3) {
                        Some(lo) if (0xDC00..=0xDFFF).contains(&lo) => {}
                        _ => return false,
                    }
                    i += 6;
                }
            }
        }
        i += 1;
    }
    true
}

enum Frame {
    Array(Vec<NodeId>),
    Object {
        entries: Vec<(String, NodeId)>,
        /// Every key so far, built once the object outgrows [`LINEAR_KEYS`] members.
        keys: Option<BTreeSet<String>>,
        pending: String,
    },
}

/// Objects up to this many members detect duplicate keys by comparing against the earlier
/// members; larger ones keep a set so the check stays logarithmic.
const LINEAR_KEYS: usize = 16;

/// Whether `key` repeats a member of `entries`, the members stored so far.
fn duplicate_key(
    entries: &[(String, NodeId)],
    keys: &mut Option<BTreeSet<String>>,
    key: &str,
) -> bool {
    if let Some(set) = keys {
        return !set.insert(String::from(key));
    }
    if entries.iter().any(|e| e.0 == key) {
        return true;
    }
    if entries.len() >= LINEAR_KEYS {
        let mut set: BTreeSet<String> = entries.iter().map(|e| e.0.clone()).collect();
        set.insert(String::from(key));
        *keys = Some(set);
    }
    false
}

struct Scanner<'a> {
    src: &'a str,
    text: &'a [u8],
    pos: usize,
    count: usize,
    max_depth: usize,
    max_values: usize,
    limit_hit: bool,
    doc: Doc,
}

impl Scanner<'_> {
    fn skip_space(&mut self) {
        while matches!(self.text.get(self.pos), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.pos += 1;
        }
    }

    fn literal(&mut self, word: &[u8]) -> bool {
        if self.text[self.pos..].starts_with(word) {
            self.pos += word.len();
            true
        } else {
            false
        }
    }

    fn digits(&mut self) -> bool {
        let start = self.pos;
        while self.text.get(self.pos).is_some_and(u8::is_ascii_digit) {
            self.pos += 1;
        }
        self.pos > start
    }

    fn number(&mut self) -> bool {
        if self.text[self.pos] == b'-' {
            self.pos += 1;
        }
        let Some(&c) = self.text.get(self.pos) else {
            return false;
        };
        if c == b'0' {
            self.pos += 1;
        } else if !self.digits() {
            return false;
        }
        if self.text.get(self.pos) == Some(&b'.') {
            self.pos += 1;
            if !self.digits() {
                return false;
            }
        }
        if matches!(self.text.get(self.pos), Some(b'e' | b'E')) {
            self.pos += 1;
            if matches!(self.text.get(self.pos), Some(b'+' | b'-')) {
                self.pos += 1;
            }
            if !self.digits() {
                return false;
            }
        }
        true
    }

    fn hex4(&self, at: usize) -> Option<i32> {
        let d = self.text.get(at..at + 4)?;
        d.iter().try_fold(0i32, |acc, &c| {
            Some(acc << 4 | char::from(c).to_digit(16)? as i32)
        })
    }

    /// Reads a quoted string starting at the opening quote.
    fn string(&mut self) -> Option<String> {
        self.pos += 1;
        // Most strings have no escapes: copy the run up to the closing quote in one piece.
        let run = self.text[self.pos..]
            .iter()
            .position(|&c| c == b'"' || c == b'\\' || c < 0x20);
        if let Some(n) = run
            && self.text[self.pos + n] == b'"'
        {
            // `src` is valid UTF-8 and the run ends at an ASCII quote, so only the start needs
            // checking to be a character boundary.
            let s = self.src.get(self.pos..self.pos + n)?;
            self.pos += n + 1;
            return Some(String::from(s));
        }
        let mut out: Vec<u8> = Vec::new();
        while let Some(&c) = self.text.get(self.pos) {
            match c {
                b'"' => {
                    self.pos += 1;
                    return String::from_utf8(out).ok();
                }
                c if c < 0x20 => return None,
                b'\\' => {
                    self.pos += 1;
                    let e = *self.text.get(self.pos)?;
                    match e {
                        b'"' | b'\\' | b'/' => out.push(e),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'n' => out.push(b'\n'),
                        b'r' => out.push(b'\r'),
                        b't' => out.push(b'\t'),
                        b'u' => {
                            let mut r = self.hex4(self.pos + 1)?;
                            self.pos += 4;
                            if (0xD800..=0xDBFF).contains(&r) {
                                let lo = self.hex4(self.pos + 3);
                                let lo = lo.filter(|_| {
                                    self.text.get(self.pos + 1) == Some(&b'\\')
                                        && self.text.get(self.pos + 2) == Some(&b'u')
                                })?;
                                r = 0x10000 + ((r - 0xD800) << 10) + (lo - 0xDC00);
                                self.pos += 6;
                            }
                            let ch = char::from_u32(r as u32).unwrap_or('\u{FFFD}');
                            let mut buf = [0u8; 4];
                            out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                        }
                        _ => return None,
                    }
                    self.pos += 1;
                }
                c => {
                    out.push(c);
                    self.pos += 1;
                }
            }
        }
        None
    }

    fn push(&mut self, node: Node) -> NodeId {
        self.doc.nodes.push(node);
        (self.doc.nodes.len() - 1) as NodeId
    }

    /// Parses the member key and colon at an object member position.
    fn member_key(&mut self) -> Option<String> {
        self.skip_space();
        if self.text.get(self.pos) != Some(&b'"') {
            return None;
        }
        let key = self.string()?;
        self.skip_space();
        if self.text.get(self.pos) != Some(&b':') {
            return None;
        }
        self.pos += 1;
        Some(key)
    }

    fn parse(&mut self) -> Option<NodeId> {
        let mut stack: Vec<Frame> = Vec::new();
        'value: loop {
            // value(depth)
            self.count += 1;
            if self.count > self.max_values {
                self.limit_hit = true;
                return None;
            }
            self.skip_space();
            let c = *self.text.get(self.pos)?;
            let mut done = match c {
                b'n' => {
                    let ok = self.literal(b"null");
                    ok.then(|| self.push(Node::Null))?
                }
                b't' => {
                    let ok = self.literal(b"true");
                    ok.then(|| self.push(Node::Bool(true)))?
                }
                b'f' => {
                    let ok = self.literal(b"false");
                    ok.then(|| self.push(Node::Bool(false)))?
                }
                b'"' => {
                    let s = self.string()?;
                    self.push(Node::Str(s))
                }
                b'-' | b'0'..=b'9' => {
                    let start = self.pos;
                    if !self.number() {
                        return None;
                    }
                    let text = String::from(self.src.get(start..self.pos)?);
                    self.push(Node::Number(text))
                }
                b'[' | b'{' => {
                    if stack.len() + 1 > self.max_depth {
                        self.limit_hit = true;
                        return None;
                    }
                    self.pos += 1;
                    self.skip_space();
                    let close = if c == b'[' { b']' } else { b'}' };
                    if self.text.get(self.pos) == Some(&close) {
                        self.pos += 1;
                        self.push(if c == b'[' {
                            Node::Array(Vec::new())
                        } else {
                            Node::Object(Vec::new())
                        })
                    } else if c == b'[' {
                        stack.push(Frame::Array(Vec::new()));
                        continue 'value;
                    } else {
                        let pending = self.member_key()?;
                        stack.push(Frame::Object {
                            entries: Vec::new(),
                            keys: None,
                            pending,
                        });
                        continue 'value;
                    }
                }
                _ => return None,
            };
            // The value `done` is complete: attach it to its container, closing containers.
            loop {
                let Some(top) = stack.last_mut() else {
                    return Some(done);
                };
                let closer = match top {
                    Frame::Array(items) => {
                        items.push(done);
                        b']'
                    }
                    Frame::Object {
                        entries, pending, ..
                    } => {
                        entries.push((core::mem::take(pending), done));
                        b'}'
                    }
                };
                self.skip_space();
                let sep = *self.text.get(self.pos)?;
                self.pos += 1;
                if sep == closer {
                    let node = match stack.pop()? {
                        Frame::Array(items) => Node::Array(items),
                        Frame::Object { entries, .. } => Node::Object(entries),
                    };
                    done = self.push(node);
                    continue;
                }
                if sep != b',' {
                    return None;
                }
                if matches!(stack.last(), Some(Frame::Object { .. })) {
                    let key = self.member_key()?;
                    if let Some(Frame::Object {
                        entries,
                        keys,
                        pending,
                    }) = stack.last_mut()
                    {
                        // The previous member was just stored, so `entries` holds every earlier key.
                        if duplicate_key(entries, keys, &key) {
                            return None;
                        }
                        *pending = key;
                    }
                }
                continue 'value;
            }
        }
    }
}

/// Parses one JSON value, returning the document and the root node.
pub fn parse(text: &str, limits: Limits) -> Result<(Doc, NodeId), Fail> {
    let (max_bytes, max_depth, max_values) = (
        budget(limits.max_bytes)?,
        budget(limits.max_depth)?,
        budget(limits.max_values)?,
    );
    if text.len() > max_bytes {
        return Err(Fail::LimitExceeded);
    }
    // Surrogate escapes only exist in text that has a backslash.
    if text.as_bytes().contains(&b'\\') && !unicode_valid(text.as_bytes()) {
        return Err(Fail::InvalidData);
    }
    let mut p = Scanner {
        src: text,
        text: text.as_bytes(),
        pos: 0,
        count: 0,
        max_depth: max_depth.min(DEPTH_CEILING),
        max_values,
        limit_hit: false,
        doc: Doc::default(),
    };
    let root = p.parse();
    let ok = root.is_some_and(|_| {
        p.skip_space();
        p.pos == text.len()
    });
    match (ok, root) {
        (true, Some(root)) => Ok((p.doc, root)),
        _ if p.limit_hit => Err(Fail::LimitExceeded),
        _ => Err(Fail::InvalidData),
    }
}

/// Whether `s` is exactly one JSON number.
pub fn number_text_valid(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let mut p = Scanner {
        src: s,
        text: s.as_bytes(),
        pos: 0,
        count: 0,
        max_depth: 0,
        max_values: 0,
        limit_hit: false,
        doc: Doc::default(),
    };
    p.number() && p.pos == s.len()
}

// ---- serialization ----

struct Out {
    buf: Vec<u8>,
    max: usize,
    overflow: bool,
}

impl Out {
    fn write(&mut self, s: &[u8]) -> Result<(), ()> {
        if s.len() > self.max - self.buf.len() {
            self.overflow = true;
            return Err(());
        }
        self.buf.extend_from_slice(s);
        Ok(())
    }

    /// Encodes a string, escaping only quotes, backslashes and control characters.
    fn string(&mut self, s: &str) -> Result<(), ()> {
        if s.len() > self.max - self.buf.len() {
            self.overflow = true;
            return Err(());
        }
        let mut enc: Vec<u8> = Vec::with_capacity(s.len() + 2);
        enc.push(b'"');
        for c in s.chars() {
            match c {
                '"' => enc.extend_from_slice(b"\\\""),
                '\\' => enc.extend_from_slice(b"\\\\"),
                '\u{8}' => enc.extend_from_slice(b"\\b"),
                '\u{c}' => enc.extend_from_slice(b"\\f"),
                '\n' => enc.extend_from_slice(b"\\n"),
                '\r' => enc.extend_from_slice(b"\\r"),
                '\t' => enc.extend_from_slice(b"\\t"),
                c if (c as u32) < 0x20 => {
                    const HEX: &[u8; 16] = b"0123456789abcdef";
                    let v = c as u32;
                    enc.extend_from_slice(b"\\u");
                    for shift in [12, 8, 4, 0] {
                        enc.push(HEX[(v >> shift & 0xf) as usize]);
                    }
                }
                c => {
                    let mut buf = [0u8; 4];
                    enc.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
                }
            }
        }
        enc.push(b'"');
        self.write(&enc)
    }
}

impl Doc {
    pub fn add(&mut self, node: Node) -> NodeId {
        self.nodes.push(node);
        (self.nodes.len() - 1) as NodeId
    }

    /// Serializes `root`. `Err(InvalidData)` for an invalid number text or a dangling node,
    /// `Err(LimitExceeded)` when the output would exceed `max_bytes`.
    pub fn stringify(
        &self,
        root: NodeId,
        max_bytes: Option<i64>,
        indent: Option<i64>,
    ) -> Result<String, Fail> {
        let max = budget(max_bytes)?;
        let width = match indent {
            None => 0,
            Some(n) => usize::try_from(n).map_err(|_| Fail::InvalidInput)?,
        }
        .min(INDENT_CEILING);
        let mut out = Out {
            buf: Vec::new(),
            max,
            overflow: false,
        };
        match self.emit(root, width, &mut out) {
            Ok(()) => String::from_utf8(out.buf).map_err(|_| Fail::InvalidData),
            Err(()) if out.overflow => Err(Fail::LimitExceeded),
            Err(()) => Err(Fail::InvalidData),
        }
    }

    /// A container child under `parents` containers must stay within what `parse` accepts.
    fn check_depth(&self, child: NodeId, parents: usize) -> Result<(), ()> {
        let container = matches!(
            self.nodes.get(child as usize),
            Some(Node::Array(_) | Node::Object(_))
        );
        if container && parents >= DEPTH_CEILING {
            return Err(());
        }
        Ok(())
    }

    fn emit(&self, root: NodeId, width: usize, out: &mut Out) -> Result<(), ()> {
        let newline = |out: &mut Out, level: usize| -> Result<(), ()> {
            if width == 0 {
                return Ok(());
            }
            let mut s = alloc::vec![b'\n'];
            s.resize(1 + width * level, b' ');
            out.write(&s)
        };
        // (node, next child index)
        let mut stack: Vec<(NodeId, usize)> = alloc::vec![(root, 0)];
        let node_at = |id: NodeId| self.nodes.get(id as usize).ok_or(());
        while let Some(&(id, next)) = stack.last() {
            let level = stack.len() - 1;
            match node_at(id)? {
                Node::Null => out.write(b"null")?,
                Node::Bool(b) => out.write(if *b { b"true" } else { b"false" })?,
                Node::Str(s) => out.string(s)?,
                Node::Number(t) => {
                    if !number_text_valid(t) {
                        return Err(());
                    }
                    out.write(t.as_bytes())?
                }
                Node::Array(items) => {
                    if items.is_empty() {
                        out.write(b"[]")?;
                    } else {
                        if next == 0 {
                            out.write(b"[")?;
                        }
                        if next < items.len() {
                            if next > 0 {
                                out.write(b",")?;
                            }
                            newline(out, level + 1)?;
                            let last = stack.len() - 1;
                            stack[last].1 = next + 1;
                            self.check_depth(items[next], stack.len())?;
                            stack.push((items[next], 0));
                            continue;
                        }
                        newline(out, level)?;
                        out.write(b"]")?;
                    }
                }
                Node::Object(entries) => {
                    if entries.is_empty() {
                        out.write(b"{}")?;
                    } else {
                        if next == 0 {
                            out.write(b"{")?;
                        }
                        if next < entries.len() {
                            if next > 0 {
                                out.write(b",")?;
                            }
                            newline(out, level + 1)?;
                            out.string(&entries[next].0)?;
                            out.write(if width > 0 { b": " } else { b":" })?;
                            let last = stack.len() - 1;
                            stack[last].1 = next + 1;
                            self.check_depth(entries[next].1, stack.len())?;
                            stack.push((entries[next].1, 0));
                            continue;
                        }
                        newline(out, level)?;
                        out.write(b"}")?;
                    }
                }
            }
            stack.pop();
        }
        Ok(())
    }
}

// ---- scalar codecs ----

/// Go's `json.Marshal(float64)`: shortest round-trip digits, exponent form outside
/// `1e-6 <= |v| < 1e21`. `None` for NaN and infinities (encoded as `null`).
pub fn float_text(v: f64) -> Option<String> {
    use core::fmt::Write;
    if !v.is_finite() {
        return None;
    }
    let abs = v.abs();
    let mut sci = String::new();
    let _ = write!(sci, "{abs:e}");
    let (mant, exp) = sci.split_once('e')?;
    let exp: i32 = exp.parse().ok()?;
    let digits: String = mant.chars().filter(|c| *c != '.').collect();
    let mut out = String::new();
    if v.is_sign_negative() {
        out.push('-');
    }
    if abs != 0.0 && !(1e-6..1e21).contains(&abs) {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        out.push(if exp < 0 { '-' } else { '+' });
        let e = exp.unsigned_abs();
        if e < 10 && exp >= 0 {
            out.push('0');
        }
        let _ = write!(out, "{e}");
        return Some(out);
    }
    let point = exp + 1; // digits before the decimal point
    if point <= 0 {
        out.push_str("0.");
        for _ in 0..-point {
            out.push('0');
        }
        out.push_str(&digits);
    } else if digits.len() as i32 <= point {
        out.push_str(&digits);
        for _ in 0..(point - digits.len() as i32) {
            out.push('0');
        }
    } else {
        out.push_str(&digits[..point as usize]);
        out.push('.');
        out.push_str(&digits[point as usize..]);
    }
    Some(out)
}

/// `strconv.ParseInt(text, 10, 64)` on number text.
pub fn parse_int(text: &str) -> Option<i64> {
    text.parse::<i64>().ok()
}

/// `strconv.ParseFloat(text, 64)` rejecting infinities.
pub fn parse_float(text: &str) -> Option<f64> {
    let v: f64 = text.parse().ok()?;
    v.is_finite().then_some(v)
}
