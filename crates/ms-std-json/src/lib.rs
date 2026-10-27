//! `@std/json.ms` natives a strict JSON parser that
//! keeps number text verbatim and rejects duplicate keys, trailing values and unpaired surrogate
//! escapes, and a serializer.
//!
//! Values live in an arena ([`Doc`]) so that neither side needs the other's value layout: the
//! parser builds a [`Doc`], the generated typed decoders read it through node ids, and typed
//! encoders build a [`Doc`] that [`Doc::stringify`] serializes. Both walks are iterative, so
//! nesting up to the 100 000 level ceiling cannot overflow the native stack.
//!
//! A [`Doc`] allocates a handful of vectors however large the document is: strings and numbers
//! are [`Span`]s into one text buffer (the parsed source, followed by decoded escapes), and
//! parsed containers are ranges of two shared pools. An untyped parse skips the document:
//! [`parse_tree`] builds the `JsonValue` through a [`TreeBuilder`] while scanning.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::Fail;
use ms_rt::tree::TreeBuilder;

/// The deepest container nesting `parse` accepts.
pub const DEPTH_CEILING: usize = 100_000;
/// The widest indent `stringify` honors.
pub const INDENT_CEILING: usize = 10;

pub type NodeId = u32;

/// A byte range of [`Doc::text`].
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Span {
    pub off: u32,
    pub len: u32,
}

/// An object member: its key and value node.
#[derive(Clone, Copy, Debug)]
pub struct Member {
    pub key: Span,
    pub val: NodeId,
}

#[derive(Clone, Copy, Debug)]
pub enum Node {
    Null,
    Bool(bool),
    /// Exact number text that is known to be a JSON number.
    Num(Span),
    /// Number text from a caller; `stringify` checks it.
    RawNum(Span),
    Str(Span),
    /// A parsed array: `len` items from `Doc::items[start..]`.
    Arr {
        start: u32,
        len: u32,
    },
    /// A parsed object: `len` members from `Doc::members[start..]`, keys unique.
    Obj {
        start: u32,
        len: u32,
    },
    /// A built array, an index into `Doc::arrays`.
    ArrB(u32),
    /// A built object in insertion order with unique keys, an index into `Doc::objects`.
    ObjB(u32),
}

#[derive(Clone, Copy, Default)]
pub struct Limits {
    pub max_bytes: Option<i64>,
    pub max_depth: Option<i64>,
    pub max_values: Option<i64>,
}

#[derive(Default, Clone)]
pub struct Doc {
    pub nodes: Vec<Node>,
    text: String,
    items: Vec<NodeId>,
    members: Vec<Member>,
    arrays: Vec<Vec<NodeId>>,
    objects: Vec<Vec<Member>>,
}

fn budget(o: Option<i64>) -> Result<usize, Fail> {
    match o {
        None => Ok(usize::MAX),
        Some(n) => usize::try_from(n).map_err(|_| Fail::InvalidInput),
    }
}

impl Doc {
    pub fn node(&self, id: NodeId) -> Option<&Node> {
        self.nodes.get(id as usize)
    }

    /// The text of `span`.
    pub fn slice(&self, span: Span) -> &str {
        let start = span.off as usize;
        self.text
            .get(start..start + span.len as usize)
            .unwrap_or("")
    }

    /// The text of a string or number node, else `""`.
    pub fn text_of(&self, id: NodeId) -> &str {
        match self.node(id) {
            Some(Node::Num(s) | Node::RawNum(s) | Node::Str(s)) => self.slice(*s),
            _ => "",
        }
    }

    /// The items of an array node, else none.
    pub fn items(&self, id: NodeId) -> &[NodeId] {
        match self.node(id) {
            Some(&Node::Arr { start, len }) => self
                .items
                .get(start as usize..(start + len) as usize)
                .unwrap_or(&[]),
            Some(&Node::ArrB(i)) => self.arrays.get(i as usize).map_or(&[], Vec::as_slice),
            _ => &[],
        }
    }

    /// The members of an object node, else none.
    pub fn members(&self, id: NodeId) -> &[Member] {
        match self.node(id) {
            Some(&Node::Obj { start, len }) => self
                .members
                .get(start as usize..(start + len) as usize)
                .unwrap_or(&[]),
            Some(&Node::ObjB(i)) => self.objects.get(i as usize).map_or(&[], Vec::as_slice),
            _ => &[],
        }
    }

    /// The members of an object node as owned key and value pairs; none for another node.
    pub fn object_entries(&self, id: NodeId) -> Option<Vec<(String, NodeId)>> {
        matches!(self.node(id), Some(Node::Obj { .. } | Node::ObjB(_))).then(|| {
            self.members(id)
                .iter()
                .map(|m| (String::from(self.slice(m.key)), m.val))
                .collect()
        })
    }

    pub fn add(&mut self, node: Node) -> NodeId {
        self.nodes.push(node);
        (self.nodes.len() - 1) as NodeId
    }

    fn put_text(&mut self, s: &str) -> Span {
        let off = self.text.len();
        self.text.push_str(s);
        Span {
            off: off as u32,
            len: s.len() as u32,
        }
    }

    pub fn add_str(&mut self, s: &str) -> NodeId {
        let span = self.put_text(s);
        self.add(Node::Str(span))
    }

    /// A number whose text `stringify` still has to check.
    pub fn add_raw_number(&mut self, s: &str) -> NodeId {
        let span = self.put_text(s);
        self.add(Node::RawNum(span))
    }

    pub fn add_array(&mut self, ids: Vec<NodeId>) -> NodeId {
        self.arrays.push(ids);
        let i = (self.arrays.len() - 1) as u32;
        self.add(Node::ArrB(i))
    }

    /// An object from members in order; a repeated key keeps its first position and last value.
    pub fn add_object(&mut self) -> NodeId {
        self.objects.push(Vec::new());
        let i = (self.objects.len() - 1) as u32;
        self.add(Node::ObjB(i))
    }

    /// An empty built array with room for `n` items.
    pub fn add_array_with_capacity(&mut self, n: usize) -> NodeId {
        self.add_array(Vec::with_capacity(n))
    }

    /// An empty built object with room for `n` members.
    pub fn add_object_with_capacity(&mut self, n: usize) -> NodeId {
        self.objects.push(Vec::with_capacity(n));
        let i = (self.objects.len() - 1) as u32;
        self.add(Node::ObjB(i))
    }

    /// Appends a member to a built object whose keys the caller keeps distinct.
    pub fn object_add(&mut self, obj: NodeId, key: &str, item: NodeId) {
        let Some(&Node::ObjB(i)) = self.node(obj) else {
            return;
        };
        let key = self.put_text(key);
        self.objects[i as usize].push(Member { key, val: item });
    }

    /// Appends an item to a built array; other nodes are left alone.
    pub fn array_push(&mut self, arr: NodeId, item: NodeId) {
        if let Some(&Node::ArrB(i)) = self.node(arr) {
            self.arrays[i as usize].push(item);
        }
    }

    /// Sets a member of a built object, replacing the value of an existing key.
    pub fn object_put(&mut self, obj: NodeId, key: &str, item: NodeId) {
        let Some(&Node::ObjB(i)) = self.node(obj) else {
            return;
        };
        let existing = self.objects[i as usize]
            .iter()
            .position(|m| self.slice(m.key) == key);
        match existing {
            Some(at) => self.objects[i as usize][at].val = item,
            None => {
                let key = self.put_text(key);
                self.objects[i as usize].push(Member { key, val: item });
            }
        }
    }

    /// Copies every node of `other` into this document, returning the offset to add to its ids.
    pub fn append(&mut self, other: &Doc) -> NodeId {
        let base = self.nodes.len() as NodeId;
        let text = self.text.len() as u32;
        let items = self.items.len() as u32;
        let members = self.members.len() as u32;
        let arrays = self.arrays.len() as u32;
        let objects = self.objects.len() as u32;
        let span = |s: Span| Span {
            off: s.off + text,
            len: s.len,
        };
        let member = |m: &Member| Member {
            key: span(m.key),
            val: m.val + base,
        };
        self.text.push_str(&other.text);
        self.items.extend(other.items.iter().map(|i| i + base));
        self.members.extend(other.members.iter().map(member));
        self.arrays.extend(
            other
                .arrays
                .iter()
                .map(|a| a.iter().map(|i| i + base).collect()),
        );
        self.objects
            .extend(other.objects.iter().map(|o| o.iter().map(member).collect()));
        self.nodes.extend(other.nodes.iter().map(|n| match *n {
            Node::Num(s) => Node::Num(span(s)),
            Node::RawNum(s) => Node::RawNum(span(s)),
            Node::Str(s) => Node::Str(span(s)),
            Node::Arr { start, len } => Node::Arr {
                start: start + items,
                len,
            },
            Node::Obj { start, len } => Node::Obj {
                start: start + members,
                len,
            },
            Node::ArrB(i) => Node::ArrB(i + arrays),
            Node::ObjB(i) => Node::ObjB(i + objects),
            n => n,
        }));
        base
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

const ONES: u64 = 0x0101_0101_0101_0101;
const HIGHS: u64 = 0x8080_8080_8080_8080;

use ms_rt::scan::{
    json_plain_digits, json_simple_number, json_special as find_special, push_member_name,
    push_member_quoted, push_short, push_string_short, skip_spaces,
};

enum Frame {
    /// An array whose items so far are `vals[start..]`.
    Array { start: usize },
    /// An object whose members so far are `mem[start..]`; the last one awaits its value.
    Object { start: usize },
}

/// Objects up to this many members detect duplicate keys by pairwise comparison; larger ones
/// hash their keys.
const LINEAR_KEYS: usize = 12;

fn hash_key(k: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325 ^ k.len() as u64;
    for c in k.chunks(8) {
        let mut w = [0u8; 8];
        w[..c.len()].copy_from_slice(c);
        h = (h.rotate_left(5) ^ u64::from_le_bytes(w)).wrapping_mul(0x517c_c1b7_2722_0a95);
    }
    h ^ (h >> 29)
}

/// Advances `pos` over ASCII digits; false when there were none.
fn scan_digits(text: &[u8], pos: &mut usize) -> bool {
    let start = *pos;
    // Eight digits at a time: a byte is a digit when `b ^ 0x30` is below ten.
    while let Some(chunk) = text.get(*pos..*pos + 8) {
        let w = u64::from_le_bytes([
            chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
        ]) ^ (ONES * 0x30);
        let non_digit = (w.wrapping_add(ONES * 0x76) | w) & HIGHS;
        if non_digit != 0 {
            *pos += (non_digit.trailing_zeros() / 8) as usize;
            return *pos > start;
        }
        *pos += 8;
    }
    while text.get(*pos).is_some_and(u8::is_ascii_digit) {
        *pos += 1;
    }
    *pos > start
}

/// Advances `pos` over one JSON number; false when the text there is not one.
fn scan_number(text: &[u8], pos: &mut usize) -> bool {
    if text.get(*pos) == Some(&b'-') {
        *pos += 1;
    }
    let Some(&c) = text.get(*pos) else {
        return false;
    };
    if c == b'0' {
        *pos += 1;
    } else if !scan_digits(text, pos) {
        return false;
    }
    if text.get(*pos) == Some(&b'.') {
        *pos += 1;
        if !scan_digits(text, pos) {
            return false;
        }
    }
    if matches!(text.get(*pos), Some(b'e' | b'E')) {
        *pos += 1;
        if matches!(text.get(*pos), Some(b'+' | b'-')) {
            *pos += 1;
        }
        if !scan_digits(text, pos) {
            return false;
        }
    }
    true
}

struct Scanner<'a> {
    src: &'a str,
    text: &'a [u8],
    pos: usize,
    count: usize,
    max_depth: usize,
    max_values: usize,
    limit_hit: bool,
    /// Whether the last string was decoded into `doc.text` rather than read from `src`.
    decoded: bool,
    doc: Doc,
    /// Open-addressing scratch table for [`Scanner::has_duplicate`].
    table: Vec<u32>,
}

impl Scanner<'_> {
    fn skip_space(&mut self) {
        let b = self.text;
        let mut p = self.pos;
        // Compact documents have no space; indented ones have a newline and a run of spaces.
        while let Some(&c) = b.get(p) {
            if c > b' ' || !matches!(c, b' ' | b'\t' | b'\n' | b'\r') {
                break;
            }
            p = skip_spaces(b, p + 1);
        }
        self.pos = p;
    }

    fn literal(&mut self, word: &[u8]) -> bool {
        if self.text[self.pos..].starts_with(word) {
            self.pos += word.len();
            true
        } else {
            false
        }
    }

    fn number(&mut self) -> bool {
        scan_number(self.text, &mut self.pos)
    }

    fn hex4(&self, at: usize) -> Option<u32> {
        let d = self.text.get(at..at + 4)?;
        d.iter()
            .try_fold(0u32, |acc, &c| Some(acc << 4 | char::from(c).to_digit(16)?))
    }

    /// Reads a quoted string starting at the opening quote. A string without escapes is a span
    /// of the source; otherwise its decoded text is appended to the document's text.
    fn string(&mut self) -> Option<Span> {
        let start = self.pos + 1;
        let end = find_special(self.text, start)?;
        if self.text[end] == b'"' {
            self.pos = end + 1;
            self.decoded = false;
            return Some(Span {
                off: start as u32,
                len: (end - start) as u32,
            });
        }
        self.escaped_string(start, end)
    }

    /// The rest of a string whose first escape or control character is at `at`.
    fn escaped_string(&mut self, start: usize, mut at: usize) -> Option<Span> {
        self.decoded = true;
        let off = self.doc.text.len();
        // `src` is valid UTF-8 and runs end at ASCII bytes, so they are character boundaries.
        self.doc.text.push_str(self.src.get(start..at)?);
        loop {
            match *self.text.get(at)? {
                b'"' => {
                    self.pos = at + 1;
                    return Some(Span {
                        off: off as u32,
                        len: (self.doc.text.len() - off) as u32,
                    });
                }
                b'\\' => {
                    self.pos = at + 1;
                    let e = *self.text.get(self.pos)?;
                    let ch = match e {
                        b'"' | b'\\' | b'/' => char::from(e),
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'u' => {
                            let mut r = self.hex4(self.pos + 1)?;
                            self.pos += 4;
                            if (0xDC00..=0xDFFF).contains(&r) {
                                return None;
                            }
                            if (0xD800..=0xDBFF).contains(&r) {
                                let lo = self.hex4(self.pos + 3);
                                let lo = lo.filter(|lo| {
                                    (0xDC00..=0xDFFF).contains(lo)
                                        && self.text.get(self.pos + 1) == Some(&b'\\')
                                        && self.text.get(self.pos + 2) == Some(&b'u')
                                })?;
                                r = 0x10000 + ((r - 0xD800) << 10) + (lo - 0xDC00);
                                self.pos += 6;
                            }
                            char::from_u32(r)?
                        }
                        _ => return None,
                    };
                    self.doc.text.push(ch);
                    self.pos += 1;
                    at = self.pos;
                }
                _ => return None,
            }
            // Copy the plain run up to the next escape, quote or control character.
            let next = find_special(self.text, at)?;
            self.doc.text.push_str(self.src.get(at..next)?);
            at = next;
        }
    }

    /// Parses the member key and colon at an object member position.
    fn member_key(&mut self) -> Option<Span> {
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

    /// Whether two members of `members` share a key.
    fn has_duplicate(&mut self, members: &[Member]) -> bool {
        let doc = &self.doc;
        let key = |m: &Member| doc.slice(m.key).as_bytes();
        if members.len() <= LINEAR_KEYS {
            return members.iter().enumerate().any(|(i, m)| {
                let k = key(m);
                members[..i].iter().any(|e| key(e) == k)
            });
        }
        let size = (members.len() * 2).next_power_of_two();
        self.table.clear();
        self.table.resize(size, 0);
        let mask = size - 1;
        for (i, m) in members.iter().enumerate() {
            let k = key(m);
            let mut slot = hash_key(k) as usize & mask;
            loop {
                let e = self.table[slot];
                if e == 0 {
                    self.table[slot] = i as u32 + 1;
                    break;
                }
                if key(&members[e as usize - 1]) == k {
                    return true;
                }
                slot = (slot + 1) & mask;
            }
        }
        false
    }

    /// The text of the string `s` just read.
    fn text_of(&self, s: Span) -> &str {
        let (off, len) = (s.off as usize, s.len as usize);
        if self.decoded {
            &self.doc.text[off..off + len]
        } else {
            &self.src[off..off + len]
        }
    }

    /// Reads a string value and hands its text to `put`.
    fn string_into(&mut self, put: impl FnOnce(&str)) -> Option<()> {
        let s = self.string()?;
        put(self.text_of(s));
        // Decoded text is scratch: the next string reuses it.
        self.doc.text.clear();
        Some(())
    }

    /// Like [`Scanner::parse`], building values with `b` instead of a document.
    fn parse_tree(&mut self, b: &mut TreeBuilder<'_>) -> Option<()> {
        let mut stack: Vec<u8> = Vec::new();
        'value: loop {
            self.count += 1;
            if self.count > self.max_values {
                self.limit_hit = true;
                return None;
            }
            self.skip_space();
            let c = *self.text.get(self.pos)?;
            match c {
                b'n' => {
                    self.literal(b"null").then_some(())?;
                    b.null();
                }
                b't' => {
                    self.literal(b"true").then_some(())?;
                    b.boolean(true);
                }
                b'f' => {
                    self.literal(b"false").then_some(())?;
                    b.boolean(false);
                }
                b'"' => self.string_into(|t| b.string(t))?,
                b'-' | b'0'..=b'9' => {
                    let start = self.pos;
                    if !self.number() {
                        return None;
                    }
                    b.number(&self.src[start..self.pos]);
                }
                b'[' | b'{' => {
                    if stack.len() + 1 > self.max_depth {
                        self.limit_hit = true;
                        return None;
                    }
                    self.pos += 1;
                    self.skip_space();
                    let close = if c == b'[' { b']' } else { b'}' };
                    let array = c == b'[';
                    if array {
                        b.begin_array();
                    } else {
                        b.begin_object();
                    }
                    if self.text.get(self.pos) == Some(&close) {
                        self.pos += 1;
                        if array {
                            b.end_array();
                        } else {
                            b.end_object().then_some(())?;
                        }
                    } else {
                        if !array {
                            self.member_key_into(b)?;
                        }
                        stack.push(c);
                        continue 'value;
                    }
                }
                _ => return None,
            }
            // The value on top of `b` is complete: close the containers it ends.
            loop {
                let Some(&open) = stack.last() else {
                    return Some(());
                };
                let closer = if open == b'[' { b']' } else { b'}' };
                self.skip_space();
                let sep = *self.text.get(self.pos)?;
                self.pos += 1;
                if sep == closer {
                    stack.pop();
                    if open == b'[' {
                        b.end_array();
                    } else {
                        b.end_object().then_some(())?;
                    }
                    continue;
                }
                if sep != b',' {
                    return None;
                }
                if open == b'{' {
                    self.member_key_into(b)?;
                }
                continue 'value;
            }
        }
    }

    fn member_key_into(&mut self, b: &mut TreeBuilder<'_>) -> Option<()> {
        let key = self.member_key()?;
        b.key(self.text_of(key));
        self.doc.text.clear();
        Some(())
    }

    fn parse(&mut self) -> Option<NodeId> {
        let mut stack: Vec<Frame> = Vec::new();
        // Completed children of the open arrays and members of the open objects.
        let mut vals: Vec<NodeId> = Vec::new();
        let mut mem: Vec<Member> = Vec::new();
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
                    ok.then(|| self.doc.add(Node::Null))?
                }
                b't' => {
                    let ok = self.literal(b"true");
                    ok.then(|| self.doc.add(Node::Bool(true)))?
                }
                b'f' => {
                    let ok = self.literal(b"false");
                    ok.then(|| self.doc.add(Node::Bool(false)))?
                }
                b'"' => {
                    let s = self.string()?;
                    self.doc.add(Node::Str(s))
                }
                b'-' | b'0'..=b'9' => {
                    let start = self.pos;
                    if !self.number() {
                        return None;
                    }
                    self.doc.add(Node::Num(Span {
                        off: start as u32,
                        len: (self.pos - start) as u32,
                    }))
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
                        self.doc.add(if c == b'[' {
                            Node::Arr { start: 0, len: 0 }
                        } else {
                            Node::Obj { start: 0, len: 0 }
                        })
                    } else if c == b'[' {
                        stack.push(Frame::Array { start: vals.len() });
                        continue 'value;
                    } else {
                        let key = self.member_key()?;
                        stack.push(Frame::Object { start: mem.len() });
                        mem.push(Member { key, val: 0 });
                        continue 'value;
                    }
                }
                _ => return None,
            };
            // The value `done` is complete: attach it to its container, closing containers.
            loop {
                let Some(top) = stack.last() else {
                    return Some(done);
                };
                let closer = match top {
                    Frame::Array { .. } => {
                        vals.push(done);
                        b']'
                    }
                    Frame::Object { .. } => {
                        mem.last_mut()?.val = done;
                        b'}'
                    }
                };
                self.skip_space();
                let sep = *self.text.get(self.pos)?;
                self.pos += 1;
                if sep == closer {
                    let node = match stack.pop()? {
                        Frame::Array { start } => {
                            let at = self.doc.items.len() as u32;
                            self.doc.items.extend_from_slice(&vals[start..]);
                            let len = (vals.len() - start) as u32;
                            vals.truncate(start);
                            Node::Arr { start: at, len }
                        }
                        Frame::Object { start } => {
                            if self.has_duplicate(&mem[start..]) {
                                return None;
                            }
                            let at = self.doc.members.len() as u32;
                            self.doc.members.extend_from_slice(&mem[start..]);
                            let len = (mem.len() - start) as u32;
                            mem.truncate(start);
                            Node::Obj { start: at, len }
                        }
                    };
                    done = self.doc.add(node);
                    continue;
                }
                if sep != b',' {
                    return None;
                }
                if matches!(stack.last(), Some(Frame::Object { .. })) {
                    let key = self.member_key()?;
                    mem.push(Member { key, val: 0 });
                }
                continue 'value;
            }
        }
    }
}

/// The depth and value budgets of a parse of `text` under `limits`; fails when the text is over
/// its byte budget.
fn budgets(text: &str, limits: Limits) -> Result<(usize, usize), Fail> {
    let (max_bytes, max_depth, max_values) = (
        budget(limits.max_bytes)?,
        budget(limits.max_depth)?,
        budget(limits.max_values)?,
    );
    if text.len() > max_bytes {
        return Err(Fail::LimitExceeded);
    }
    // Spans are 32-bit offsets.
    if u32::try_from(text.len()).is_err() {
        return Err(Fail::LimitExceeded);
    }
    Ok((max_depth.min(DEPTH_CEILING), max_values))
}

fn scanner(text: &str, max_depth: usize, max_values: usize, doc: Doc) -> Scanner<'_> {
    Scanner {
        src: text,
        text: text.as_bytes(),
        pos: 0,
        count: 0,
        max_depth,
        max_values,
        limit_hit: false,
        decoded: false,
        doc,
        table: Vec::new(),
    }
}

/// The failure of a parse that did not succeed.
fn failure(text: &str, limit_hit: bool) -> Fail {
    // Go's decoder would replace what the escape scan rejects, which outranks a limit.
    if text.as_bytes().contains(&b'\\') && !unicode_valid(text.as_bytes()) {
        Fail::InvalidData
    } else if limit_hit {
        Fail::LimitExceeded
    } else {
        Fail::InvalidData
    }
}

/// Parses one JSON value, returning the document and the root node.
pub fn parse(text: &str, limits: Limits) -> Result<(Doc, NodeId), Fail> {
    let (max_depth, max_values) = budgets(text, limits)?;
    let mut doc = Doc::default();
    doc.text.reserve(text.len() + text.len() / 16);
    doc.text.push_str(text);
    // About one node per eight bytes of typical documents.
    doc.nodes.reserve(text.len() / 8);
    doc.items.reserve(text.len() / 16);
    doc.members.reserve(text.len() / 32);
    let mut p = scanner(text, max_depth, max_values, doc);
    let root = p.parse();
    let ok = root.is_some_and(|_| {
        p.skip_space();
        p.pos == text.len()
    });
    match (ok, root) {
        // Decoded escapes grew the text past what a span can address.
        (true, Some(_)) if u32::try_from(p.doc.text.len()).is_err() => Err(Fail::LimitExceeded),
        (true, Some(root)) => Ok((p.doc, root)),
        _ => Err(failure(text, p.limit_hit)),
    }
}

/// Parses one JSON value into `b`, which holds the root afterwards; on failure `b` is left to be
/// dropped.
pub fn parse_tree(text: &str, limits: Limits, b: &mut TreeBuilder<'_>) -> Result<(), Fail> {
    let (max_depth, max_values) = budgets(text, limits)?;
    let mut p = scanner(text, max_depth, max_values, Doc::default());
    let ok = p.parse_tree(b).is_some() && {
        p.skip_space();
        p.pos == text.len()
    };
    if ok {
        Ok(())
    } else {
        Err(failure(text, p.limit_hit))
    }
}

/// Whether `s` is exactly one JSON number.
pub fn number_text_valid(s: &str) -> bool {
    let mut pos = 0;
    scan_number(s.as_bytes(), &mut pos) && pos == s.len()
}

// ---- serialization ----

struct Out {
    buf: Vec<u8>,
    max: usize,
    overflow: bool,
}

impl Out {
    fn check(&mut self) -> Result<(), ()> {
        if self.buf.len() > self.max {
            self.overflow = true;
            return Err(());
        }
        Ok(())
    }

    fn write(&mut self, s: &[u8]) -> Result<(), ()> {
        self.buf.extend_from_slice(s);
        self.check()
    }

    /// Encodes a string, escaping only quotes, backslashes and control characters.
    fn string(&mut self, s: &str) -> Result<(), ()> {
        const HEX: &[u8; 16] = b"0123456789abcdef";
        let b = s.as_bytes();
        self.buf.reserve(b.len() + 2);
        self.buf.push(b'"');
        let mut at = 0;
        while let Some(i) = find_special(b, at) {
            self.buf.extend_from_slice(&b[at..i]);
            match b[i] {
                b'"' => self.buf.extend_from_slice(b"\\\""),
                b'\\' => self.buf.extend_from_slice(b"\\\\"),
                8 => self.buf.extend_from_slice(b"\\b"),
                12 => self.buf.extend_from_slice(b"\\f"),
                b'\n' => self.buf.extend_from_slice(b"\\n"),
                b'\r' => self.buf.extend_from_slice(b"\\r"),
                b'\t' => self.buf.extend_from_slice(b"\\t"),
                c => self.buf.extend_from_slice(&[
                    b'\\',
                    b'u',
                    b'0',
                    b'0',
                    HEX[usize::from(c >> 4)],
                    HEX[usize::from(c & 0xf)],
                ]),
            }
            at = i + 1;
        }
        self.buf.extend_from_slice(&b[at..]);
        self.buf.push(b'"');
        self.check()
    }

    fn newline(&mut self, width: usize, level: usize) -> Result<(), ()> {
        if width == 0 {
            return Ok(());
        }
        self.buf.push(b'\n');
        self.buf.resize(self.buf.len() + width * level, b' ');
        self.check()
    }
}

impl Doc {
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
            buf: Vec::with_capacity(self.text.len().min(max)),
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
            self.node(child),
            Some(Node::Arr { .. } | Node::Obj { .. } | Node::ArrB(_) | Node::ObjB(_))
        );
        if container && parents >= DEPTH_CEILING {
            return Err(());
        }
        Ok(())
    }

    fn emit(&self, root: NodeId, width: usize, out: &mut Out) -> Result<(), ()> {
        // (node, next child index)
        let mut stack: Vec<(NodeId, usize)> = alloc::vec![(root, 0)];
        while let Some(&(id, next)) = stack.last() {
            let level = stack.len() - 1;
            match self.node(id).ok_or(())? {
                Node::Null => out.write(b"null")?,
                Node::Bool(b) => out.write(if *b { b"true" } else { b"false" })?,
                Node::Str(s) => out.string(self.slice(*s))?,
                Node::Num(t) => out.write(self.slice(*t).as_bytes())?,
                Node::RawNum(t) => {
                    let t = self.slice(*t);
                    if !number_text_valid(t) {
                        return Err(());
                    }
                    out.write(t.as_bytes())?
                }
                Node::Arr { .. } | Node::ArrB(_) => {
                    let items = self.items(id);
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
                            out.newline(width, level + 1)?;
                            let last = stack.len() - 1;
                            stack[last].1 = next + 1;
                            self.check_depth(items[next], stack.len())?;
                            stack.push((items[next], 0));
                            continue;
                        }
                        out.newline(width, level)?;
                        out.write(b"]")?;
                    }
                }
                Node::Obj { .. } | Node::ObjB(_) => {
                    let members = self.members(id);
                    if members.is_empty() {
                        out.write(b"{}")?;
                    } else {
                        if next == 0 {
                            out.write(b"{")?;
                        }
                        if next < members.len() {
                            if next > 0 {
                                out.write(b",")?;
                            }
                            out.newline(width, level + 1)?;
                            out.string(self.slice(members[next].key))?;
                            out.write(if width > 0 { b": " } else { b":" })?;
                            let last = stack.len() - 1;
                            stack[last].1 = next + 1;
                            self.check_depth(members[next].val, stack.len())?;
                            stack.push((members[next].val, 0));
                            continue;
                        }
                        out.newline(width, level)?;
                        out.write(b"}")?;
                    }
                }
            }
            stack.pop();
        }
        Ok(())
    }
}

// ---- streaming writer ----

#[derive(Clone, Copy, Default)]
struct Level {
    /// Members or items written so far.
    count: u32,
    /// Where the last separator started and the count then, for [`Writer::undo`].
    undo_len: usize,
    undo_count: u32,
}

/// "00" to "99": two digits per step when writing integers.
static PAIRS: [u8; 200] = {
    let mut t = [0u8; 200];
    let mut i = 0;
    while i < 100 {
        t[i * 2] = b'0' + (i / 10) as u8;
        t[i * 2 + 1] = b'0' + (i % 10) as u8;
        i += 1;
    }
    t
};

/// The letter after the backslash that escapes each byte, `u` for `\u00xx`, 0 for none.
const ESCAPES: [u8; 256] = {
    let mut t = [0u8; 256];
    let mut c = 0;
    while c < 0x20 {
        t[c] = b'u';
        c += 1;
    }
    t[b'"' as usize] = b'"';
    t[b'\\' as usize] = b'\\';
    t[8] = b'b';
    t[12] = b'f';
    t[b'\n' as usize] = b'n';
    t[b'\r' as usize] = b'r';
    t[b'\t' as usize] = b't';
    t
};

/// Writes JSON text straight into a buffer: typed encoders call it in document order and never
/// build a [`Doc`]. A failure (`max_bytes`, a number that is not JSON, nesting past
/// [`DEPTH_CEILING`], a bad budget) is kept and every later call does nothing.
pub struct Writer {
    /// UTF-8: only whole `&str`s and ASCII are appended, and [`Writer::undo`] cuts at a recorded length.
    buf: Vec<u8>,
    max: usize,
    width: usize,
    err: Option<Fail>,
    levels: Vec<Level>,
    /// A value without a JSON form was left out.
    pub lost: bool,
}

impl Writer {
    pub fn new(max_bytes: Option<i64>, indent: Option<i64>) -> Writer {
        let mut err = None;
        let max = budget(max_bytes).unwrap_or_else(|e| {
            err = Some(e);
            usize::MAX
        });
        let width = match indent {
            None => 0,
            Some(n) => usize::try_from(n).unwrap_or_else(|_| {
                err = Some(Fail::InvalidInput);
                0
            }),
        }
        .min(INDENT_CEILING);
        Writer {
            buf: Vec::with_capacity(256.min(max)),
            max,
            width,
            err,
            levels: Vec::new(),
            lost: false,
        }
    }

    fn check(&mut self) {
        if self.buf.len() > self.max {
            self.err.get_or_insert(Fail::LimitExceeded);
        }
    }

    fn fail(&mut self) {
        self.err.get_or_insert(Fail::InvalidData);
    }

    fn newline(&mut self, level: usize) {
        if self.width > 0 {
            self.buf.push(b'\n');
            self.buf.resize(self.buf.len() + self.width * level, b' ');
        }
    }

    /// The separator before a member or item of the open container.
    fn separate(&mut self) {
        let depth = self.levels.len();
        let Some(top) = self.levels.last_mut() else {
            return;
        };
        top.undo_len = self.buf.len();
        top.undo_count = top.count;
        let comma = top.count > 0;
        top.count += 1;
        if comma {
            self.buf.push(b',');
        }
        self.newline(depth);
    }

    /// Starts an item of the open array.
    pub fn item(&mut self) {
        if self.err.is_none() {
            self.separate();
        }
    }

    /// Starts member `key` of the open object.
    pub fn key(&mut self, key: &str) {
        if self.err.is_some() {
            return;
        }
        if self.width == 0
            && let Some(top) = self.levels.last_mut()
        {
            let at = self.buf.len();
            if push_member_name(&mut self.buf, top.count > 0, key.as_bytes()) {
                top.undo_len = at;
                top.undo_count = top.count;
                top.count += 1;
                self.check();
                return;
            }
        }
        self.buf.reserve(key.len() + 8);
        self.separate();
        self.quoted(key);
        self.buf.push(b':');
        if self.width > 0 {
            self.buf.push(b' ');
        }
        self.check();
    }

    /// Starts a member whose name is already escaped: `quoted_name` is the name with its quotes.
    pub fn key_quoted(&mut self, quoted_name: &str) {
        if self.err.is_some() {
            return;
        }
        if self.width == 0
            && let Some(top) = self.levels.last_mut()
        {
            let at = self.buf.len();
            if push_member_quoted(&mut self.buf, top.count > 0, quoted_name.as_bytes()) {
                top.undo_len = at;
                top.undo_count = top.count;
                top.count += 1;
                self.check();
                return;
            }
        }
        self.separate();
        push_short(&mut self.buf, quoted_name.as_bytes());
        self.buf.push(b':');
        if self.width > 0 {
            self.buf.push(b' ');
        }
        self.check();
    }

    /// Removes the last [`Writer::item`] or [`Writer::key`] and whatever followed it.
    pub fn undo(&mut self) {
        if self.err.is_some() {
            return;
        }
        if let Some(top) = self.levels.last_mut() {
            self.buf.truncate(top.undo_len);
            top.count = top.undo_count;
        }
    }

    fn open(&mut self, c: u8) {
        if self.err.is_some() {
            return;
        }
        if self.levels.len() >= DEPTH_CEILING {
            self.fail();
            return;
        }
        self.buf.push(c);
        self.levels.push(Level::default());
        self.check();
    }

    fn close(&mut self, c: u8) {
        if self.err.is_some() {
            return;
        }
        let Some(level) = self.levels.pop() else {
            return self.fail();
        };
        if level.count > 0 {
            self.newline(self.levels.len());
        }
        self.buf.push(c);
        self.check();
    }

    pub fn begin_array(&mut self) {
        self.open(b'[');
    }
    pub fn end_array(&mut self) {
        self.close(b']');
    }
    pub fn begin_object(&mut self) {
        self.open(b'{');
    }
    pub fn end_object(&mut self) {
        self.close(b'}');
    }

    pub fn null(&mut self) {
        self.raw("null");
    }

    pub fn boolean(&mut self, v: bool) {
        self.raw(if v { "true" } else { "false" });
    }

    pub fn int(&mut self, v: i64) {
        if self.err.is_some() {
            return;
        }
        if v < 0 {
            self.buf.push(b'-');
        }
        let mut digits = [0u8; 20];
        let mut at = digits.len();
        let mut n = v.unsigned_abs();
        while n >= 100 {
            let pair = (n % 100) as usize * 2;
            n /= 100;
            at -= 2;
            digits[at] = PAIRS[pair];
            digits[at + 1] = PAIRS[pair + 1];
        }
        if n >= 10 {
            at -= 2;
            digits[at] = PAIRS[n as usize * 2];
            digits[at + 1] = PAIRS[n as usize * 2 + 1];
        } else {
            at -= 1;
            digits[at] = b'0' + n as u8;
        }
        push_short(&mut self.buf, &digits[at..]);
        self.check();
    }

    /// A float; NaN and infinities are `null`.
    pub fn float(&mut self, v: f64) {
        if self.err.is_some() {
            return;
        }
        if float_append(&mut self.buf, v).is_none() {
            self.null();
            return;
        }
        self.check();
    }

    /// Number text from a caller, which has to be one JSON number.
    pub fn number(&mut self, text: &str) {
        if self.err.is_some() {
            return;
        }
        let b = text.as_bytes();
        if !(b.len() <= 16 && json_plain_digits(b))
            && !json_simple_number(b)
            && !number_text_valid(text)
        {
            return self.fail();
        }
        self.raw(text);
    }

    pub fn string(&mut self, text: &str) {
        if self.err.is_some() {
            return;
        }
        self.quoted(text);
        self.check();
    }

    fn raw(&mut self, text: &str) {
        if self.err.is_none() {
            push_short(&mut self.buf, text.as_bytes());
            self.check();
        }
    }

    fn quoted(&mut self, s: &str) {
        let b = s.as_bytes();
        // Most names and short values: no escape, one capacity check.
        if push_string_short(&mut self.buf, b) {
            return;
        }
        self.buf.reserve(b.len() + 2);
        self.buf.push(b'"');
        let mut at = 0;
        while let Some(i) = find_special(b, at) {
            push_short(&mut self.buf, &b[at..i]);
            self.escape(b[i], ESCAPES[usize::from(b[i])]);
            at = i + 1;
        }
        push_short(&mut self.buf, &b[at..]);
        self.buf.push(b'"');
    }

    /// The escape of byte `c`, whose [`ESCAPES`] entry is `code`.
    fn escape(&mut self, c: u8, code: u8) {
        const HEX: &[u8; 16] = b"0123456789abcdef";
        if code == b'u' {
            self.buf.extend_from_slice(&[
                b'\\',
                b'u',
                b'0',
                b'0',
                HEX[usize::from(c >> 4)],
                HEX[usize::from(c & 0xf)],
            ]);
        } else {
            self.buf.extend_from_slice(&[b'\\', code]);
        }
    }

    /// The text written, or the first failure.
    pub fn finish(&mut self) -> Result<String, Fail> {
        match self.err {
            Some(e) => Err(e),
            None if !self.levels.is_empty() => Err(Fail::InvalidData),
            // Only whole `&str`s and ASCII were appended, and `undo` cuts at a recorded boundary.
            None => Ok(ms_rt::scan::string_from_valid_utf8(core::mem::take(
                &mut self.buf,
            ))),
        }
    }
}

// ---- scalar codecs ----

/// Go's `json.Marshal(float64)`: shortest round-trip digits, exponent form outside
/// `1e-6 <= |v| < 1e21`. `None` for NaN and infinities (encoded as `null`).
pub fn float_text(v: f64) -> Option<String> {
    let mut out = Vec::new();
    float_append(&mut out, v)?;
    String::from_utf8(out).ok()
}

/// Fixed-size text for the `{:e}` form of a float: at most 17 digits, a point, and an exponent.
struct Sci {
    bytes: [u8; 32],
    len: usize,
}

impl core::fmt::Write for Sci {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        let end = self.len + s.len();
        self.bytes
            .get_mut(self.len..end)
            .ok_or(core::fmt::Error)?
            .copy_from_slice(s.as_bytes());
        self.len = end;
        Ok(())
    }
}

/// Powers of ten that a double holds exactly.
const POW10: [f64; 23] = [
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16,
    1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
];

/// The shortest digits of `abs` (1e-6 <= abs < 1e15) when it is a decimal of at most 15
/// significant digits, written to `buf` with the decimal exponent of the first digit. Two
/// different 15-digit decimals never round to one double, so a decimal that divides back to `abs`
/// is the only candidate and, once trailing zeros are dropped, the shortest one: the same digits
/// the shortest-round-trip formatter finds.
fn short_digits(abs: f64, buf: &mut [u8; 24]) -> Option<(usize, i32)> {
    if !(1e-6..1e15).contains(&abs) {
        return None;
    }
    // floor(log10(abs)) from the binary exponent: right or one too low or high, which the
    // 15-digit range below catches and the second try fixes.
    let e2 = ((abs.to_bits() >> 52) & 0x7ff) as i32 - 1023;
    let mut exp = (e2 * 1233) >> 12;
    let (mut scale, mut n, mut pow);
    let mut tries = 0;
    loop {
        scale = 14 - exp; // 10^scale puts 15 digits before the point
        pow = *POW10.get(usize::try_from(scale).ok()?)?;
        n = (abs * pow + 0.5) as u64; // rounds to nearest; the check below catches a bad tie
        tries += 1;
        if n >= 1_000_000_000_000_000 && tries < 3 {
            exp += 1;
        } else if n < 100_000_000_000_000 && tries < 3 {
            exp -= 1;
        } else {
            break;
        }
    }
    if !(100_000_000_000_000..1_000_000_000_000_000).contains(&n) || n as f64 / pow != abs {
        return None;
    }
    // Drop trailing zeros, then write what is left from the end.
    let mut len = 15;
    for (step, zeros) in [(100_000_000, 8), (10_000, 4), (100, 2), (10, 1)] {
        if n % step == 0 {
            n /= step;
            len -= zeros;
        }
    }
    // Two digits per step, as in `Writer::int`.
    let mut at = len;
    while n >= 100 {
        let pair = (n % 100) as usize * 2;
        n /= 100;
        at -= 2;
        buf[at] = PAIRS[pair];
        buf[at + 1] = PAIRS[pair + 1];
    }
    if at == 2 {
        buf[0] = PAIRS[n as usize * 2];
        buf[1] = PAIRS[n as usize * 2 + 1];
    } else {
        buf[0] = b'0' + n as u8;
    }
    Some((len, 14 - scale))
}

/// The shortest round-trip digits of `abs` through the standard formatter, as in
/// [`short_digits`].
fn sci_digits(abs: f64, buf: &mut [u8; 24]) -> Option<(usize, i32)> {
    use core::fmt::Write;
    let mut sci = Sci {
        bytes: [0; 32],
        len: 0,
    };
    write!(sci, "{abs:e}").ok()?;
    let text = &sci.bytes[..sci.len];
    let e_at = text.iter().position(|&c| c == b'e')?;
    let exp: i32 = core::str::from_utf8(&text[e_at + 1..]).ok()?.parse().ok()?;
    let mut n = 0;
    for &c in &text[..e_at] {
        if c != b'.' {
            *buf.get_mut(n)? = c;
            n += 1;
        }
    }
    Some((n, exp))
}

const POW10_INT: [u64; 5] = [1, 10, 100, 1000, 10000];

/// Writes the decimal digits of `n` (none for zero) so that they end just before `end`, two at a
/// time, and returns where they start.
#[inline(always)]
fn put_digits(buf: &mut [u8; 24], mut end: usize, mut n: u64) -> usize {
    while n >= 100 {
        let pair = (n % 100) as usize * 2;
        n /= 100;
        end -= 2;
        buf[end] = PAIRS[pair];
        buf[end + 1] = PAIRS[pair + 1];
    }
    if n >= 10 {
        end -= 2;
        buf[end] = PAIRS[n as usize * 2];
        buf[end + 1] = PAIRS[n as usize * 2 + 1];
    } else if n > 0 {
        end -= 1;
        buf[end] = b'0' + n as u8;
    }
    end
}

/// Writes `v` when it is a decimal with one to four fraction digits and at most 15 digits in all
/// (`12345.5`, `0.25`, `99.99`), by scaling to an integer and checking that it divides back to
/// `abs`: the quotient of an exact integer by an exact power of ten is the correctly rounded
/// double of that decimal, so a match is the digits the shortest-round-trip formatter finds, and
/// the first scale that matches is the fewest fraction digits. Anything else returns false and
/// writes nothing.
fn short_fraction(out: &mut Vec<u8>, v: f64, abs: f64) -> bool {
    if !(1e-3..1e11).contains(&abs) {
        return false;
    }
    for (k, pow) in [(1usize, 10.0), (2, 100.0), (3, 1000.0), (4, 10000.0)] {
        // Below 1e15 either way, so the signed conversions (cheaper than unsigned ones) are exact.
        let n = (abs * pow + 0.5) as i64;
        if n as f64 / pow != abs {
            continue;
        }
        let n = n as u64;
        let scale = POW10_INT[k];
        // `n` has no trailing zero here: one fewer fraction digit would have matched first.
        // The buffer starts as zeros, so a short fraction keeps its leading zeros.
        let mut text = [b'0'; 24];
        let mut at = 24 - k;
        put_digits(&mut text, 24, n % scale);
        at -= 1;
        text[at] = b'.';
        let start = put_digits(&mut text, at, n / scale);
        at = if start == at { at - 1 } else { start };
        if v.is_sign_negative() {
            out.push(b'-');
        }
        push_short(out, &text[at..]);
        return true;
    }
    false
}

/// Appends [`float_text`] to `out`; `None` (and nothing appended) for NaN and infinities.
fn float_append(out: &mut Vec<u8>, v: f64) -> Option<()> {
    if !v.is_finite() {
        return None;
    }
    let abs = v.abs();
    if abs < 1e15 && (abs as i64) as f64 == abs {
        // A whole number prints as its digits, with no point or exponent.
        if v.is_sign_negative() {
            out.push(b'-');
        }
        let mut digits = [b'0'; 24];
        let start = put_digits(&mut digits, 24, abs as u64);
        // Zero has no digits from `put_digits`; its one `0` is already in the buffer.
        let at = start.min(23);
        push_short(out, &digits[at..]);
        return Some(());
    }
    if short_fraction(out, v, abs) {
        return Some(());
    }
    let mut buf = [0u8; 24];
    let (n, exp) = match short_digits(abs, &mut buf) {
        Some(found) => found,
        None => sci_digits(abs, &mut buf)?,
    };
    let digits = &buf[..n];
    if v.is_sign_negative() {
        out.push(b'-');
    }
    if abs != 0.0 && !(1e-6..1e21).contains(&abs) {
        out.push(digits[0]);
        if n > 1 {
            out.push(b'.');
            push_short(out, &digits[1..]);
        }
        out.push(b'e');
        out.push(if exp < 0 { b'-' } else { b'+' });
        let e = exp.unsigned_abs();
        if e < 10 && exp >= 0 {
            out.push(b'0');
        }
        if e >= 100 {
            out.push(b'0' + (e / 100) as u8);
        }
        if e >= 10 {
            out.push(b'0' + (e / 10 % 10) as u8);
        }
        out.push(b'0' + (e % 10) as u8);
        return Some(());
    }
    let point = exp + 1; // digits before the decimal point
    if point <= 0 {
        push_short(out, b"0.");
        out.resize(out.len() + (-point) as usize, b'0');
        push_short(out, digits);
    } else if n as i32 <= point {
        push_short(out, digits);
        out.resize(out.len() + (point - n as i32) as usize, b'0');
    } else {
        push_short(out, &digits[..point as usize]);
        out.push(b'.');
        push_short(out, &digits[point as usize..]);
    }
    Some(())
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
