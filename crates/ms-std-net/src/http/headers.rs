//! `HttpHeaders`: an ordered multimap of names to byte values.

use crate::error::HttpErr;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, OnceLock};

/// A headers collection shared between handles (`HttpHeaders` values alias).
pub type Shared = Rc<RefCell<Headers>>;

/// One name and where its bytes sit in a [`Table`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Slot {
    name: u32,
    name_len: u32,
    value: u32,
    value_len: u32,
}

/// The most bytes a table holds; offsets and lengths are `u32` to keep a slot at 16 bytes. A
/// received head is bounded by the server's header limit, far below this.
const MAX_BYTES: usize = u32::MAX as usize;

impl Slot {
    /// A slot for spans that fit [`MAX_BYTES`], which `Table::room` checked.
    fn new(name: usize, name_len: usize, value: usize, value_len: usize) -> Slot {
        debug_assert!(
            [name + name_len, value + value_len]
                .iter()
                .all(|&end| end <= MAX_BYTES)
        );
        Slot {
            name: name as u32,
            name_len: name_len as u32,
            value: value as u32,
            value_len: value_len as u32,
        }
    }

    fn name_span(&self) -> std::ops::Range<usize> {
        self.name as usize..(self.name + self.name_len) as usize
    }

    fn value_span(&self) -> std::ops::Range<usize> {
        self.value as usize..(self.value + self.value_len) as usize
    }
}

/// Every name and value of a collection in one buffer, with one slot per value.
///
/// A table is either in order or raw. In order, the slots of one name are adjacent and share the
/// name's bytes. A raw table is a received head: the slots are in arrival order with the names
/// as they came, which costs a copy of the head and one slot per field and nothing more. The
/// canonical, sorted and grouped form is built the first time something enumerates the headers,
/// and kept; a lookup by name needs neither.
#[derive(Clone, Debug, Default)]
struct Table {
    buf: Vec<u8>,
    slots: Vec<Slot>,
    raw: bool,
    view: OnceLock<Box<Table>>,
}

impl Table {
    fn name(&self, slot: &Slot) -> &str {
        let bytes = &self.buf[slot.name_span()];
        debug_assert!(std::str::from_utf8(bytes).is_ok());
        // SAFETY: every writer of name bytes copies a whole `&str` (`add_bytes`,
        // `from_received`, and `from_parsed`, whose names are httparse `&str`s and whose copy
        // keeps each name's bytes together), and `canonicalize` changes only ASCII letters to the
        // other case, so a name's span is always valid UTF-8.
        unsafe { std::str::from_utf8_unchecked(bytes) }
    }

    fn value(&self, slot: &Slot) -> &[u8] {
        &self.buf[slot.value_span()]
    }

    fn named(&self, slot: &Slot, name: &str) -> bool {
        self.name(slot).eq_ignore_ascii_case(name)
    }

    /// The table in order: itself, or for a raw one its canonical sorted form.
    fn ordered(&self) -> &Table {
        if !self.raw {
            return self;
        }
        self.view.get_or_init(|| Box::new(self.in_order()))
    }

    fn in_order(&self) -> Table {
        let mut table = Table {
            buf: self.buf.clone(),
            slots: self.slots.clone(),
            raw: false,
            view: OnceLock::new(),
        };
        for slot in &table.slots {
            canonicalize(&mut table.buf[slot.name_span()]);
        }
        table.grouped(false)
    }

    /// The end of the group of slots that starts at `start`, in an ordered table.
    fn group_end(&self, start: usize) -> usize {
        let name = self.slots[start].name;
        start
            + self.slots[start..]
                .iter()
                .take_while(|s| s.name == name)
                .count()
    }

    /// The start and end of the group of `name`, in an ordered table.
    fn find_group(&self, name: &str) -> Option<(usize, usize)> {
        let mut at = 0;
        while at < self.slots.len() {
            let end = self.group_end(at);
            if self.named(&self.slots[at], name) {
                return Some((at, end));
            }
            at = end;
        }
        None
    }

    /// Whether `extra` more bytes keep every offset within [`MAX_BYTES`].
    fn room(&self, extra: usize) -> bool {
        self.buf
            .len()
            .checked_add(extra)
            .is_some_and(|n| n <= MAX_BYTES)
    }

    fn push_bytes(&mut self, bytes: &[u8]) -> usize {
        let at = self.buf.len();
        self.buf.extend_from_slice(bytes);
        at
    }

    /// The slots sorted by name, equal names merged into one group in arrival order.
    fn grouped(mut self, fold: bool) -> Table {
        let buf = std::mem::take(&mut self.buf);
        let name_of = |s: &Slot| &buf[s.name_span()];
        // A stable sort by name keeps arrival order within a name; the slots of a name then share
        // the bytes of the first one's spelling.
        if fold {
            self.slots.sort_by(|a, b| {
                name_of(a)
                    .iter()
                    .map(u8::to_ascii_lowercase)
                    .cmp(name_of(b).iter().map(u8::to_ascii_lowercase))
            });
        } else {
            self.slots.sort_by(|a, b| name_of(a).cmp(name_of(b)));
        }
        let mut first: Option<Slot> = None;
        for slot in &mut self.slots {
            match first {
                Some(head) if name_of(&head).eq_ignore_ascii_case(name_of(slot)) => {
                    slot.name = head.name;
                    slot.name_len = head.name_len;
                }
                _ => first = Some(*slot),
            }
        }
        self.buf = buf;
        self.raw = false;
        self.view = OnceLock::new();
        self
    }
}

/// The values of one name in arrival order.
#[derive(Clone, Copy)]
pub struct Values<'a> {
    table: &'a Table,
    slots: &'a [Slot],
    /// Which of `slots` count; all of them when absent.
    name: Option<&'a str>,
}

impl<'a> Values<'a> {
    pub fn len(&self) -> usize {
        self.iter().count()
    }

    pub fn is_empty(&self) -> bool {
        self.first().is_none()
    }

    pub fn iter(&self) -> ValueIter<'a> {
        ValueIter {
            table: self.table,
            slots: self.slots.iter(),
            name: self.name,
        }
    }

    pub fn first(&self) -> Option<&'a [u8]> {
        self.iter().next()
    }

    pub fn to_vec(&self) -> Vec<Vec<u8>> {
        self.iter().map(<[u8]>::to_vec).collect()
    }
}

/// The values of one name, in arrival order.
pub struct ValueIter<'a> {
    table: &'a Table,
    slots: std::slice::Iter<'a, Slot>,
    name: Option<&'a str>,
}

impl<'a> Iterator for ValueIter<'a> {
    type Item = &'a [u8];

    fn next(&mut self) -> Option<&'a [u8]> {
        let (table, name) = (self.table, self.name);
        self.slots
            .find(|s| name.is_none_or(|n| table.named(s, n)))
            .map(|s| table.value(s))
    }
}

impl<'a> IntoIterator for Values<'a> {
    type Item = &'a [u8];
    type IntoIter = ValueIter<'a>;

    fn into_iter(self) -> ValueIter<'a> {
        self.iter()
    }
}

/// One name with its values.
#[derive(Clone, Copy)]
pub struct Entry<'a> {
    pub name: &'a str,
    pub values: Values<'a>,
}

/// The entries of a collection in order.
pub struct Entries<'a> {
    table: &'a Table,
    at: usize,
}

impl<'a> Iterator for Entries<'a> {
    type Item = Entry<'a>;

    fn next(&mut self) -> Option<Entry<'a>> {
        if self.at >= self.table.slots.len() {
            return None;
        }
        let end = self.table.group_end(self.at);
        let slots = &self.table.slots[self.at..end];
        self.at = end;
        Some(Entry {
            name: self.table.name(&slots[0]),
            values: Values {
                table: self.table,
                slots,
                name: None,
            },
        })
    }
}

#[derive(Clone, Debug)]
pub struct Headers {
    /// Shared until written, so handing the received headers to a handler copies nothing.
    table: Arc<Table>,
}

thread_local! {
    /// The table of every empty `Headers` on this thread, so creating one allocates nothing.
    static EMPTY: Arc<Table> = Arc::new(Table::default());
}

/// Equal when they hold the same names and values, however the bytes are laid out.
impl PartialEq for Headers {
    fn eq(&self, other: &Headers) -> bool {
        self.pairs().eq(other.pairs())
    }
}

impl Eq for Headers {}

impl Default for Headers {
    fn default() -> Headers {
        Headers {
            table: EMPTY.with(Arc::clone),
        }
    }
}

/// The class of each byte: `TOKEN` for a byte of an RFC 9110 token (letters, digits and
/// ``!#$%&'*+-.^_`|~``), plus `UPPER` or `LOWER` for a letter, so one load answers each question
/// the canonical-name scan asks.
const TOKEN: u8 = 1;
const UPPER: u8 = 2;
const LOWER: u8 = 4;
const CLASS: [u8; 256] = {
    let mut table = [0; 256];
    let mut b = 0;
    while b < 256 {
        let c = b as u8;
        if c.is_ascii_alphanumeric()
            || matches!(
                c,
                b'!' | b'#'
                    | b'$'
                    | b'%'
                    | b'&'
                    | b'\''
                    | b'*'
                    | b'+'
                    | b'-'
                    | b'.'
                    | b'^'
                    | b'_'
                    | b'`'
                    | b'|'
                    | b'~'
            )
        {
            table[b] = TOKEN;
        }
        if c.is_ascii_uppercase() {
            table[b] |= UPPER;
        }
        if c.is_ascii_lowercase() {
            table[b] |= LOWER;
        }
        b += 1;
    }
    table
};

/// Token characters of RFC 9110.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty() && name.bytes().all(|b| CLASS[b as usize] & TOKEN != 0)
}

/// Whether `bytes` is UTF-8: ASCII, which most values are, is checked a word at a time.
pub fn is_utf8(bytes: &[u8]) -> bool {
    bytes.is_ascii() || std::str::from_utf8(bytes).is_ok()
}

/// Outgoing values are UTF-8 text with no control bytes besides tab, and no DEL.
pub fn valid_value(value: &[u8]) -> bool {
    is_utf8(value) && value.iter().all(|&b| (b >= 32 || b == b'\t') && b != 127)
}

/// `textproto.CanonicalMIMEHeaderKey`: keys with a space or non-token byte are
/// returned as they are.
pub fn canonical(name: &str) -> String {
    canonical_owned(name.to_string())
}

/// `canonical` over an owned name: one pass finds whether the name is a token and already
/// canonical (nearly every name a client sends is), and only a name that is not is rebuilt.
pub fn canonical_owned(name: String) -> String {
    // The letter case a canonical byte must not have: lower after the first byte and after a
    // hyphen, upper elsewhere; any byte of that case, or a byte outside the token, ends the scan.
    let mut wrong = LOWER;
    let (mut canonical, mut all_token) = (true, true);
    for b in name.bytes() {
        let class = CLASS[b as usize];
        all_token &= class & TOKEN != 0;
        canonical &= class & wrong == 0;
        wrong = if b == b'-' { LOWER } else { UPPER };
    }
    if !all_token || canonical || name.is_empty() {
        return name;
    }
    // A name that is not canonical is edited in place; its bytes are ASCII tokens, so they stay
    // UTF-8.
    let mut bytes = name.into_bytes();
    let mut upper = true;
    for b in &mut bytes {
        let was = *b;
        if upper {
            b.make_ascii_uppercase();
        } else {
            b.make_ascii_lowercase();
        }
        upper = was == b'-';
    }
    String::from_utf8(bytes).unwrap_or_default()
}

impl Headers {
    pub fn new() -> Headers {
        Headers::default()
    }

    /// The entries, canonical names sorted for received headers, in order of first use for
    /// built ones.
    pub fn entries(&self) -> Entries<'_> {
        Entries {
            table: self.table.ordered(),
            at: 0,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.table.slots.is_empty()
    }

    /// Every (name, value) pair, grouped by name.
    pub fn pairs(&self) -> impl Iterator<Item = (&str, &[u8])> {
        let table = self.table.ordered();
        table
            .slots
            .iter()
            .map(move |s| (table.name(s), table.value(s)))
    }

    /// Every (name, value) pair in the order stored, names as they came: the fields of a
    /// received head without building the canonical form. Names compare case-insensitively.
    pub fn raw_pairs(&self) -> impl Iterator<Item = (&str, &[u8])> {
        let table = &*self.table;
        table
            .slots
            .iter()
            .map(move |s| (table.name(s), table.value(s)))
    }

    /// The table to write: in order, and not shared with another handle.
    fn own(&mut self) -> &mut Table {
        let table = Arc::make_mut(&mut self.table);
        if table.raw {
            *table = table.in_order();
        }
        table
    }

    /// Adds a value under `name` without validating it.
    pub fn add(&mut self, name: &str, value: Vec<u8>) {
        let _ = self.add_bytes(name, &value);
    }

    fn add_bytes(&mut self, name: &str, value: &[u8]) -> Result<(), HttpErr> {
        let table = self.own();
        if !table.room(name.len().saturating_add(value.len())) {
            return Err(HttpErr::LimitExceeded);
        }
        let value_at = table.push_bytes(value);
        match table.find_group(name) {
            Some((first, end)) => {
                let head = table.slots[first];
                let slot = Slot::new(
                    head.name as usize,
                    head.name_len as usize,
                    value_at,
                    value.len(),
                );
                table.slots.insert(end, slot);
            }
            None => {
                let name_at = table.push_bytes(name.as_bytes());
                table
                    .slots
                    .push(Slot::new(name_at, name.len(), value_at, value.len()));
            }
        }
        Ok(())
    }

    /// `HttpHeaders.append`: the name must be a token.
    pub fn append(&mut self, name: &str, value: &[u8]) -> Result<(), HttpErr> {
        if !valid_name(name) {
            return Err(HttpErr::InvalidInput);
        }
        self.add_bytes(name, value)
    }

    pub fn values<'a>(&'a self, name: &'a str) -> Option<Values<'a>> {
        let table = &*self.table;
        let values = Values {
            table,
            slots: &table.slots,
            name: Some(name),
        };
        (!values.is_empty()).then_some(values)
    }

    /// The first value of `name`, if any.
    pub fn first<'a>(&'a self, name: &str) -> Option<&'a [u8]> {
        let table = &*self.table;
        let slot = table.slots.iter().find(|s| table.named(s, name))?;
        Some(table.value(slot))
    }

    /// `HttpHeaders.text`: values as UTF-8 text.
    pub fn text(&self, name: &str) -> Result<Option<Vec<String>>, HttpErr> {
        let Some(values) = self.values(name) else {
            return Ok(None);
        };
        values
            .iter()
            .map(|v| String::from_utf8(v.to_vec()).map_err(|_| HttpErr::InvalidData))
            .collect::<Result<Vec<_>, _>>()
            .map(Some)
    }

    pub fn names(&self) -> Vec<&str> {
        self.entries().map(|e| e.name).collect()
    }

    pub fn remove(&mut self, name: &str) -> bool {
        if self.values(name).is_none() {
            return false;
        }
        let table = self.own();
        let Some((first, end)) = table.find_group(name) else {
            return false;
        };
        table.slots.drain(first..end);
        true
    }

    /// Replaces every value of `name` with `value`.
    pub fn set(&mut self, name: &str, value: Vec<u8>) {
        if self.values(name).is_none() {
            return self.add(name, value);
        }
        let table = self.own();
        let Some((first, end)) = table.find_group(name) else {
            return;
        };
        if !table.room(value.len()) {
            return;
        }
        let value_at = table.push_bytes(&value);
        table.slots[first].value = value_at as u32;
        table.slots[first].value_len = value.len() as u32;
        table.slots.drain(first + 1..end);
    }

    /// Received headers as handlers see them: canonical names, sorted by name, values in arrival
    /// order. The bytes of all fields go into one buffer.
    pub fn from_received<N: AsRef<str>, V: AsRef<[u8]>>(
        fields: impl IntoIterator<Item = (N, V)>,
    ) -> Headers {
        let fields = fields.into_iter();
        let mut table = Table {
            slots: Vec::with_capacity(fields.size_hint().0),
            raw: true,
            ..Table::default()
        };
        for (name, value) in fields {
            let (name, value) = (name.as_ref(), value.as_ref());
            if !table.room(name.len().saturating_add(value.len())) {
                break;
            }
            let name_at = table.push_bytes(name.as_bytes());
            let value_at = table.push_bytes(value);
            table
                .slots
                .push(Slot::new(name_at, name.len(), value_at, value.len()));
        }
        Headers {
            table: Arc::new(table),
        }
    }

    /// The headers of a parsed head. `headers` are slices of `buf`: the bytes from the first name
    /// to the last value are copied once and the slots point into the copy, so the cost grows
    /// with the number of fields by one slot each.
    pub fn from_parsed(buf: &[u8], headers: &[httparse::Header<'_>]) -> Headers {
        let (Some(first), Some(last)) = (headers.first(), headers.last()) else {
            return Headers::new();
        };
        let base = buf.as_ptr() as usize;
        let offset = |part: &[u8]| (part.as_ptr() as usize).wrapping_sub(base);
        let start = offset(first.name.as_bytes());
        let end = offset(last.value).saturating_add(last.value.len());
        if start > end || end > buf.len() || end - start > MAX_BYTES {
            return Headers::from_received(headers.iter().map(|h| (h.name, h.value)));
        }
        let mut slots = Vec::with_capacity(headers.len());
        for h in headers {
            let (name, value) = (offset(h.name.as_bytes()), offset(h.value));
            // Both spans must lie inside the region copied below.
            let inside = name >= start
                && name <= end
                && h.name.len() <= end - name
                && value >= start
                && value <= end
                && h.value.len() <= end - value;
            if !inside {
                return Headers::from_received(headers.iter().map(|h| (h.name, h.value)));
            }
            slots.push(Slot::new(
                name - start,
                h.name.len(),
                value - start,
                h.value.len(),
            ));
        }
        Headers {
            table: Arc::new(Table {
                buf: buf[start..end].to_vec(),
                slots,
                raw: true,
                view: OnceLock::new(),
            }),
        }
    }

    /// Whether every value is UTF-8. Names and separators are ASCII, so a buffer that is ASCII
    /// throughout settles it with one check.
    pub fn is_text(&self) -> bool {
        let table = &self.table;
        table.buf.is_ascii() || table.slots.iter().all(|s| is_utf8(table.value(s)))
    }

    /// Orders the entries by name (stable, so values of one name keep their order).
    pub fn sort(&mut self) {
        let table = self.own();
        *table = std::mem::take(table).grouped(true);
    }
}

/// Rewrites a token in canonical case (`content-TYPE` to `Content-Type`); anything else is left
/// as it is.
fn canonicalize(bytes: &mut [u8]) {
    if bytes.is_empty() || !bytes.iter().all(|&b| CLASS[b as usize] & TOKEN != 0) {
        return;
    }
    canonicalize_token(bytes);
}

/// `canonicalize` for bytes known to be a token.
fn canonicalize_token(bytes: &mut [u8]) {
    let mut upper = true;
    for b in bytes {
        let class = CLASS[*b as usize];
        // Flip the case bit of a letter that is in the wrong case for its place in the word.
        let wrong = if upper { class & LOWER } else { class & UPPER };
        upper = *b == b'-';
        *b ^= u8::from(wrong != 0) << 5;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_fold_case_and_keep_first_spelling() {
        let mut h = Headers::new();
        h.append("X-Dup", b"first").unwrap();
        h.append("x-dup", b"second").unwrap();
        h.append("Other", b"1").unwrap();
        assert_eq!(h.names(), vec!["X-Dup", "Other"]);
        assert_eq!(h.values("X-DUP").unwrap().len(), 2);
        assert_eq!(
            h.text("x-dup").unwrap(),
            Some(vec!["first".into(), "second".into()])
        );
        assert_eq!(h.append("bad name", b"v"), Err(HttpErr::InvalidInput));
        assert!(h.remove("OTHER"));
        assert!(!h.remove("other"));
        h.append("raw", &[0xff]).unwrap();
        assert_eq!(h.text("raw"), Err(HttpErr::InvalidData));
        assert_eq!(h.text("missing"), Ok(None));
    }

    #[test]
    fn received_headers_are_canonical_and_sorted() {
        let h = Headers::from_received(vec![
            ("x-b".to_string(), b"1".to_vec()),
            ("ACCEPT".to_string(), b"a".to_vec()),
            ("X-B".to_string(), b"2".to_vec()),
        ]);
        assert_eq!(h.names(), vec!["Accept", "X-B"]);
        assert_eq!(
            h.values("x-b").unwrap().to_vec(),
            [b"1".to_vec(), b"2".to_vec()]
        );
        assert_eq!(canonical("content-type"), "Content-Type");
        assert_eq!(canonical("a b"), "a b");
    }

    /// The per-byte definition `canonical_owned` replaces.
    fn canonical_by_bytes(name: &str) -> String {
        if name.is_empty()
            || !name
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b))
        {
            return name.to_string();
        }
        let mut upper = true;
        name.bytes()
            .map(|b| {
                let c = if upper {
                    b.to_ascii_uppercase()
                } else {
                    b.to_ascii_lowercase()
                };
                upper = b == b'-';
                c as char
            })
            .collect()
    }

    #[test]
    fn canonical_names_match_the_byte_by_byte_rule() {
        for name in [
            "",
            "a",
            "A",
            "host",
            "Host",
            "HOST",
            "content-type",
            "Content-Type",
            "X-FORWARDED-for",
            "x--y",
            "-a",
            "a-",
            "a b",
            "a:b",
            "é",
            "Ünï",
            "x_y-Z",
            "0-9",
            "ETag",
            "WWW-Authenticate",
        ] {
            assert_eq!(canonical(name), canonical_by_bytes(name), "{name:?}");
        }
        // Every pair of bytes, so each class of byte meets each state.
        for a in 0..=127u8 {
            for b in 0..=127u8 {
                let name = String::from_utf8(vec![a, b'-', b]).unwrap();
                assert_eq!(canonical(&name), canonical_by_bytes(&name), "{name:?}");
            }
        }
    }

    #[test]
    fn utf8_check_agrees_with_the_standard_one() {
        for bytes in [
            &b""[..],
            b"ascii only here",
            "ünï".as_bytes(),
            &[0xff],
            &[b'a', 0xc3],
            &[0xc3, 0xa9],
        ] {
            assert_eq!(
                is_utf8(bytes),
                std::str::from_utf8(bytes).is_ok(),
                "{bytes:?}"
            );
        }
    }

    fn parse(head: &[u8]) -> Vec<(String, Vec<u8>)> {
        let mut storage = [httparse::EMPTY_HEADER; 32];
        let mut req = httparse::Request::new(&mut storage);
        assert!(req.parse(head).unwrap().is_complete());
        req.headers
            .iter()
            .map(|h| (h.name.to_string(), h.value.to_vec()))
            .collect()
    }

    #[test]
    fn a_parsed_head_builds_the_same_table_as_the_received_fields() {
        let heads: [&[u8]; 4] = [
            b"GET / HTTP/1.1\r\n\r\n",
            b"GET / HTTP/1.1\r\nhost: h\r\n\r\n",
            b"GET / HTTP/1.1\r\nX-B: 1\r\nx-a: 2\r\nx-b: 3\r\nUSER-agent:  curl \r\nX-B: \r\n\r\n",
            b"POST /p?q=1 HTTP/1.1\r\nContent-LENGTH: 4\r\nA-b-C: \xc3\xa9\r\nA-B-c: z\r\n\r\nbody",
        ];
        for head in heads {
            let mut storage = [httparse::EMPTY_HEADER; 32];
            let mut req = httparse::Request::new(&mut storage);
            assert!(req.parse(head).unwrap().is_complete());
            let parsed = Headers::from_parsed(head, req.headers);
            let received = Headers::from_received(parse(head));
            assert_eq!(parsed, received, "{}", String::from_utf8_lossy(head));
        }
    }

    #[test]
    fn received_headers_group_values_in_arrival_order() {
        let h = Headers::from_received(parse(
            b"GET / HTTP/1.1\r\nX-B: 1\r\nx-a: 2\r\nx-b: 3\r\nHOST: h\r\n\r\n",
        ));
        assert_eq!(h.names(), ["Host", "X-A", "X-B"]);
        assert_eq!(
            h.values("x-b").unwrap().to_vec(),
            [b"1".to_vec(), b"3".to_vec()]
        );
        assert_eq!(h.first("host"), Some(&b"h"[..]));
        assert!(h.values("x-c").is_none());
    }

    #[test]
    fn writing_a_shared_table_leaves_the_other_copies_alone() {
        let a = Headers::from_received(parse(b"GET / HTTP/1.1\r\nA: 1\r\nB: 2\r\n\r\n"));
        let mut b = a.clone();
        b.set("a", b"9".to_vec());
        b.add("C", b"3".to_vec());
        assert!(b.remove("B"));
        b.sort();
        assert_eq!(b.names(), ["A", "C"]);
        assert_eq!(a.names(), ["A", "B"]);
        assert_eq!(a.first("a"), Some(&b"1"[..]));
        assert_eq!(b.first("a"), Some(&b"9"[..]));
        assert!(!b.remove("B"));
    }

    #[test]
    fn spans_outside_the_buffer_fall_back_instead_of_being_misread() {
        let elsewhere = b"X-Other: v\r\n";
        let buf = b"GET / HTTP/1.1\r\nA: 1\r\n\r\n";
        let headers = [
            httparse::Header {
                name: "X-Other",
                value: &elsewhere[9..10],
            },
            httparse::Header {
                name: "A",
                value: &buf[19..20],
            },
        ];
        let parsed = Headers::from_parsed(buf, &headers);
        assert_eq!(parsed.first("x-other"), Some(&b"v"[..]));
        assert_eq!(parsed.first("a"), Some(&b"1"[..]));
    }

    #[test]
    fn an_empty_name_or_value_at_the_end_of_the_buffer_is_kept() {
        let buf = b"Name:";
        let headers = [httparse::Header {
            name: "Name",
            value: &buf[5..5],
        }];
        let h = Headers::from_parsed(buf, &headers);
        assert_eq!(h.first("name"), Some(&b""[..]));
        assert_eq!(h.names(), ["Name"]);
        let buf = b"a: 1\r\nb:";
        let headers = [
            httparse::Header {
                name: "a",
                value: &buf[3..4],
            },
            httparse::Header {
                name: "b",
                value: &buf[8..8],
            },
        ];
        let h = Headers::from_parsed(buf, &headers);
        assert_eq!(h.names(), ["A", "B"]);
        assert_eq!(h.first("b"), Some(&b""[..]));
        assert!(Headers::from_parsed(buf, &[]).is_empty());
    }

    /// A plain model of a collection: groups of (name, values) in the order the type promises.
    #[derive(Clone, Default)]
    struct Model {
        groups: Vec<(String, Vec<Vec<u8>>)>,
    }

    impl Model {
        fn received(fields: &[(String, Vec<u8>)]) -> Model {
            let mut model = Model::default();
            for (name, value) in fields {
                model.add(&canonical(name), value.clone());
            }
            model.groups.sort_by(|a, b| a.0.cmp(&b.0));
            model
        }

        fn group(&mut self, name: &str) -> Option<&mut (String, Vec<Vec<u8>>)> {
            self.groups
                .iter_mut()
                .find(|g| g.0.eq_ignore_ascii_case(name))
        }

        fn add(&mut self, name: &str, value: Vec<u8>) {
            match self.group(name) {
                Some(g) => g.1.push(value),
                None => self.groups.push((name.to_string(), vec![value])),
            }
        }

        fn set(&mut self, name: &str, value: Vec<u8>) {
            match self.group(name) {
                Some(g) => g.1 = vec![value],
                None => self.add(name, value),
            }
        }

        fn remove(&mut self, name: &str) -> bool {
            let before = self.groups.len();
            self.groups.retain(|g| !g.0.eq_ignore_ascii_case(name));
            before != self.groups.len()
        }
    }

    fn assert_same(h: &Headers, m: &Model, what: &str) {
        let entries: Vec<(String, Vec<Vec<u8>>)> = h
            .entries()
            .map(|e| (e.name.to_string(), e.values.to_vec()))
            .collect();
        assert_eq!(entries, m.groups, "entries {what}");
        assert_eq!(
            h.names(),
            m.groups.iter().map(|g| g.0.as_str()).collect::<Vec<_>>(),
            "names {what}"
        );
        for name in NAMES {
            let want = m
                .groups
                .iter()
                .find(|g| g.0.eq_ignore_ascii_case(name))
                .map(|g| &g.1);
            assert_eq!(
                h.values(name).map(|v| v.to_vec()).as_ref(),
                want,
                "{name} {what}"
            );
            assert_eq!(
                h.first(name),
                want.and_then(|v| v.first()).map(Vec::as_slice),
                "first {name} {what}"
            );
            assert_eq!(h.values(name).map(|v| v.len()), want.map(Vec::len));
        }
    }

    const NAMES: [&str; 8] = [
        "a",
        "A",
        "b",
        "X-Y",
        "x-y",
        "content-type",
        "Content-Type",
        "Z",
    ];

    /// A small deterministic generator.
    struct Lcg(u64);

    impl Lcg {
        fn next(&mut self, n: usize) -> usize {
            self.0 = self
                .0
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            (self.0 >> 33) as usize % n
        }

        fn value(&mut self) -> Vec<u8> {
            let len = self.next(4);
            (0..len).map(|_| b"xyz1 "[self.next(5)]).collect()
        }
    }

    fn apply(rng: &mut Lcg, h: &mut Headers, m: &mut Model) {
        let name = NAMES[rng.next(NAMES.len())];
        match rng.next(3) {
            0 => {
                let v = rng.value();
                h.add(name, v.clone());
                m.add(name, v);
            }
            1 => {
                let v = rng.value();
                h.set(name, v.clone());
                m.set(name, v);
            }
            _ => assert_eq!(h.remove(name), m.remove(name)),
        }
    }

    #[test]
    fn a_table_matches_a_plain_model_through_random_writes_and_clones() {
        for seed in 0..300u64 {
            let mut rng = Lcg(seed);
            let fields: Vec<(String, Vec<u8>)> = (0..rng.next(7))
                .map(|_| (NAMES[rng.next(NAMES.len())].to_string(), rng.value()))
                .collect();
            // A received table (raw) and a built one start the same random walk.
            let mut tables = [
                (
                    Headers::from_received(fields.clone()),
                    Model::received(&fields),
                ),
                (Headers::new(), Model::default()),
            ];
            for (h, m) in &mut tables {
                assert_same(h, m, &format!("start {seed}"));
                for step in 0..12 {
                    let (mut other_h, mut other_m) = (h.clone(), m.clone());
                    // Reading before and after a write; the clone must not see the write.
                    if rng.next(2) == 0 {
                        assert_same(h, m, &format!("pre-read {seed}/{step}"));
                    }
                    apply(&mut rng, h, m);
                    assert_same(h, m, &format!("{seed}/{step}"));
                    assert_same(&other_h, &other_m, &format!("clone {seed}/{step}"));
                    apply(&mut rng, &mut other_h, &mut other_m);
                    assert_same(&other_h, &other_m, &format!("clone write {seed}/{step}"));
                    assert_same(h, m, &format!("original after clone write {seed}/{step}"));
                }
            }
        }
    }

    #[test]
    fn received_headers_are_what_handlers_saw_before_the_table() {
        // The reference: canonical names, sorted by name, values in arrival order.
        let heads: [&[u8]; 3] = [
            b"POST /p HTTP/1.1\r\nhost: h\r\nX-B: 1\r\ncontent-LENGTH: 3\r\nx-b: 2\r\nAccept: */*\r\n\r\nabc",
            b"GET / HTTP/1.0\r\n\r\n",
            b"GET / HTTP/1.1\r\nUSER-AGENT: a\r\nuser-agent: b\r\nE: \r\n\r\n",
        ];
        for head in heads {
            let fields = parse(head);
            let mut reference: Vec<(String, Vec<Vec<u8>>)> = Vec::new();
            for (name, value) in &fields {
                let name = canonical(name);
                match reference.iter_mut().find(|g| g.0 == name) {
                    Some(g) => g.1.push(value.clone()),
                    None => reference.push((name, vec![value.clone()])),
                }
            }
            reference.sort_by(|a, b| a.0.cmp(&b.0));
            let via_parser = match crate::http::h1::parse_request(head, 1 << 16) {
                crate::http::h1::Parsed::Complete(h) => h.fields,
                _ => panic!("not a request"),
            };
            // HTTP/2 and the client build from the received fields directly.
            for table in [via_parser, Headers::from_received(fields.clone())] {
                let seen: Vec<(String, Vec<Vec<u8>>)> = table
                    .entries()
                    .map(|e| (e.name.to_string(), e.values.to_vec()))
                    .collect();
                assert_eq!(seen, reference, "{}", String::from_utf8_lossy(head));
            }
        }
    }

    #[test]
    fn value_validity() {
        assert!(valid_value(b"ok\ttab"));
        assert!(!valid_value(b"a\nb"));
        assert!(!valid_value(&[127]));
        assert!(!valid_value(&[0xff]));
        assert!(valid_value("ünï".as_bytes()));
    }
}
