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
//! parsed containers are ranges of two shared pools.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::Fail;

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

/// The index of the first byte at or after `i` that a JSON string must escape (`"`, `\` or a
/// control character), eight bytes at a time.
fn find_special(b: &[u8], mut i: usize) -> Option<usize> {
    while let Some(chunk) = b.get(i..i + 8) {
        let w = u64::from_le_bytes([
            chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
        ]);
        let zero = |x: u64| x.wrapping_sub(ONES) & !x & HIGHS;
        let m = zero(w ^ (ONES * 0x22))
            | zero(w ^ (ONES * 0x5c))
            | (w.wrapping_sub(ONES * 0x20) & !w & HIGHS);
        if m != 0 {
            return Some(i + (m.trailing_zeros() / 8) as usize);
        }
        i += 8;
    }
    while let Some(&c) = b.get(i) {
        if c == b'"' || c == b'\\' || c < 0x20 {
            return Some(i);
        }
        i += 1;
    }
    None
}

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

struct Scanner<'a> {
    src: &'a str,
    text: &'a [u8],
    pos: usize,
    count: usize,
    max_depth: usize,
    max_values: usize,
    limit_hit: bool,
    doc: Doc,
    /// Open-addressing scratch table for [`Scanner::has_duplicate`].
    table: Vec<u32>,
}

impl Scanner<'_> {
    fn skip_space(&mut self) {
        // Compact documents have no space; indented ones have a newline and runs of spaces.
        while let Some(&c) = self.text.get(self.pos) {
            if c > b' ' || !matches!(c, b' ' | b'\t' | b'\n' | b'\r') {
                return;
            }
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
        // Eight digits at a time: a byte is a digit when `b ^ 0x30` is below ten.
        while let Some(chunk) = self.text.get(self.pos..self.pos + 8) {
            let w = u64::from_le_bytes([
                chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
            ]) ^ (ONES * 0x30);
            let non_digit = (w.wrapping_add(ONES * 0x76) | w) & HIGHS;
            if non_digit != 0 {
                self.pos += (non_digit.trailing_zeros() / 8) as usize;
                return self.pos > start;
            }
            self.pos += 8;
        }
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
            return Some(Span {
                off: start as u32,
                len: (end - start) as u32,
            });
        }
        self.escaped_string(start, end)
    }

    /// The rest of a string whose first escape or control character is at `at`.
    fn escaped_string(&mut self, start: usize, mut at: usize) -> Option<Span> {
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
    // Spans are 32-bit offsets.
    if u32::try_from(text.len()).is_err() {
        return Err(Fail::LimitExceeded);
    }
    let mut doc = Doc::default();
    doc.text.reserve(text.len() + text.len() / 16);
    doc.text.push_str(text);
    // About one node per eight bytes of typical documents.
    doc.nodes.reserve(text.len() / 8);
    doc.items.reserve(text.len() / 16);
    doc.members.reserve(text.len() / 32);
    let mut p = Scanner {
        src: text,
        text: text.as_bytes(),
        pos: 0,
        count: 0,
        max_depth: max_depth.min(DEPTH_CEILING),
        max_values,
        limit_hit: false,
        doc,
        table: Vec::new(),
    };
    let root = p.parse();
    let ok = root.is_some_and(|_| {
        p.skip_space();
        p.pos == text.len()
    });
    match (ok, root) {
        // Decoded escapes grew the text past what a span can address.
        (true, Some(_)) if u32::try_from(p.doc.text.len()).is_err() => Err(Fail::LimitExceeded),
        (true, Some(root)) => Ok((p.doc, root)),
        // Go's decoder would replace what the escape scan rejects, which outranks a limit.
        _ if text.as_bytes().contains(&b'\\') && !unicode_valid(text.as_bytes()) => {
            Err(Fail::InvalidData)
        }
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
        table: Vec::new(),
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

/// Writes JSON text straight into a buffer: typed encoders call it in document order and never
/// build a [`Doc`]. A failure (`max_bytes`, a number that is not JSON, nesting past
/// [`DEPTH_CEILING`], a bad budget) is kept and every later call does nothing.
pub struct Writer {
    buf: String,
    max: usize,
    width: usize,
    err: Option<Fail>,
    levels: Vec<Level>,
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
            buf: String::new(),
            max,
            width,
            err,
            levels: Vec::new(),
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
            self.buf.push('\n');
            let n = self.width * level;
            self.buf.reserve(n);
            for _ in 0..n {
                self.buf.push(' ');
            }
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
            self.buf.push(',');
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
        self.separate();
        self.quoted(key);
        self.buf.push(':');
        if self.width > 0 {
            self.buf.push(' ');
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

    fn open(&mut self, c: char) {
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

    fn close(&mut self, c: char) {
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
        self.open('[');
    }
    pub fn end_array(&mut self) {
        self.close(']');
    }
    pub fn begin_object(&mut self) {
        self.open('{');
    }
    pub fn end_object(&mut self) {
        self.close('}');
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
        let mut digits = [0u8; 20];
        let mut at = digits.len();
        let mut n = v.unsigned_abs();
        loop {
            at -= 1;
            digits[at] = b'0' + (n % 10) as u8;
            n /= 10;
            if n == 0 {
                break;
            }
        }
        if v < 0 {
            self.buf.push('-');
        }
        for &d in &digits[at..] {
            self.buf.push(char::from(d));
        }
        self.check();
    }

    /// A float; NaN and infinities are `null`.
    pub fn float(&mut self, v: f64) {
        match float_text(v) {
            Some(t) => self.raw(&t),
            None => self.null(),
        }
    }

    /// Number text from a caller, which has to be one JSON number.
    pub fn number(&mut self, text: &str) {
        if self.err.is_some() {
            return;
        }
        if !number_text_valid(text) {
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
            self.buf.push_str(text);
            self.check();
        }
    }

    fn quoted(&mut self, s: &str) {
        const HEX: &[u8; 16] = b"0123456789abcdef";
        let b = s.as_bytes();
        self.buf.reserve(b.len() + 2);
        self.buf.push('"');
        let mut at = 0;
        while let Some(i) = find_special(b, at) {
            // Runs end at ASCII bytes, so they are character boundaries.
            self.buf.push_str(s.get(at..i).unwrap_or(""));
            match b[i] {
                b'"' => self.buf.push_str("\\\""),
                b'\\' => self.buf.push_str("\\\\"),
                8 => self.buf.push_str("\\b"),
                12 => self.buf.push_str("\\f"),
                b'\n' => self.buf.push_str("\\n"),
                b'\r' => self.buf.push_str("\\r"),
                b'\t' => self.buf.push_str("\\t"),
                c => {
                    self.buf.push_str("\\u00");
                    self.buf.push(char::from(HEX[usize::from(c >> 4)]));
                    self.buf.push(char::from(HEX[usize::from(c & 0xf)]));
                }
            }
            at = i + 1;
        }
        self.buf.push_str(s.get(at..).unwrap_or(""));
        self.buf.push('"');
    }

    /// The text written, or the first failure.
    pub fn finish(&mut self) -> Result<String, Fail> {
        match self.err {
            Some(e) => Err(e),
            None if !self.levels.is_empty() => Err(Fail::InvalidData),
            None => Ok(core::mem::take(&mut self.buf)),
        }
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
