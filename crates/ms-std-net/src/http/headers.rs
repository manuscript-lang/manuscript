//! `HttpHeaders`: an ordered multimap of names to byte values.

use crate::error::HttpErr;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

/// A headers collection shared between handles (`HttpHeaders` values alias).
pub type Shared = Rc<RefCell<Headers>>;

/// One name with its values. Names compare with ASCII case folding and keep the
/// spelling of their first use.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub values: Values,
}

/// The values of one name in arrival order. Nearly every name has one, which then needs no
/// list of its own.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Values {
    One(Vec<u8>),
    Many(Vec<Vec<u8>>),
}

impl Values {
    fn push(&mut self, value: Vec<u8>) {
        match self {
            Values::Many(all) => all.push(value),
            Values::One(first) => {
                *self = Values::Many(vec![std::mem::take(first), value]);
            }
        }
    }
}

impl std::ops::Deref for Values {
    type Target = [Vec<u8>];

    fn deref(&self) -> &[Vec<u8>] {
        match self {
            Values::One(value) => std::slice::from_ref(value),
            Values::Many(all) => all,
        }
    }
}

impl<'a> IntoIterator for &'a Values {
    type Item = &'a Vec<u8>;
    type IntoIter = std::slice::Iter<'a, Vec<u8>>;

    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Headers {
    /// Shared until written, so handing the received headers to a handler copies nothing.
    entries: Arc<Vec<Entry>>,
}

thread_local! {
    /// The entries of every empty `Headers` on this thread, so creating one allocates nothing.
    static EMPTY: Arc<Vec<Entry>> = Arc::new(Vec::new());
}

impl Default for Headers {
    fn default() -> Headers {
        Headers {
            entries: EMPTY.with(Arc::clone),
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

    pub fn entries(&self) -> &[Entry] {
        &self.entries
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    fn position(&self, name: &str) -> Option<usize> {
        self.entries
            .iter()
            .position(|e| e.name.eq_ignore_ascii_case(name))
    }

    /// Adds a value under `name` without validating it.
    pub fn add(&mut self, name: &str, value: Vec<u8>) {
        match self.position(name) {
            Some(i) => Arc::make_mut(&mut self.entries)[i].values.push(value),
            None => Arc::make_mut(&mut self.entries).push(Entry {
                name: name.to_string(),
                values: Values::One(value),
            }),
        }
    }

    /// `HttpHeaders.append`: the name must be a token.
    pub fn append(&mut self, name: &str, value: &[u8]) -> Result<(), HttpErr> {
        if !valid_name(name) {
            return Err(HttpErr::InvalidInput);
        }
        self.add(name, value.to_vec());
        Ok(())
    }

    pub fn values(&self, name: &str) -> Option<&[Vec<u8>]> {
        self.position(name).map(|i| &*self.entries[i].values)
    }

    /// The first value of `name`, if any.
    pub fn first(&self, name: &str) -> Option<&[u8]> {
        self.values(name)?.first().map(Vec::as_slice)
    }

    /// `HttpHeaders.text`: values as UTF-8 text.
    pub fn text(&self, name: &str) -> Result<Option<Vec<String>>, HttpErr> {
        let Some(values) = self.values(name) else {
            return Ok(None);
        };
        values
            .iter()
            .map(|v| String::from_utf8(v.clone()).map_err(|_| HttpErr::InvalidData))
            .collect::<Result<Vec<_>, _>>()
            .map(Some)
    }

    pub fn names(&self) -> Vec<&str> {
        self.entries.iter().map(|e| e.name.as_str()).collect()
    }

    pub fn remove(&mut self, name: &str) -> bool {
        match self.position(name) {
            Some(i) => {
                Arc::make_mut(&mut self.entries).remove(i);
                true
            }
            None => false,
        }
    }

    /// Replaces every value of `name` with `value`.
    pub fn set(&mut self, name: &str, value: Vec<u8>) {
        match self.position(name) {
            Some(i) => Arc::make_mut(&mut self.entries)[i].values = Values::One(value),
            None => self.add(name, value),
        }
    }

    /// Received headers as handlers see them: canonical names, sorted
    /// by name, values in arrival order.
    pub fn from_received(fields: impl IntoIterator<Item = (String, Vec<u8>)>) -> Headers {
        let fields = fields.into_iter();
        let mut entries: Vec<Entry> = Vec::with_capacity(fields.size_hint().0);
        for (name, value) in fields {
            let key = canonical_owned(name);
            match entries.iter_mut().find(|e| e.name == key) {
                Some(e) => e.values.push(value),
                None => entries.push(Entry {
                    name: key,
                    values: Values::One(value),
                }),
            }
        }
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        Headers {
            entries: Arc::new(entries),
        }
    }

    /// Whether every name and value is UTF-8.
    pub fn is_text(&self) -> bool {
        self.entries
            .iter()
            .all(|e| e.values.iter().all(|v| is_utf8(v)))
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
        assert_eq!(h.values("x-b").unwrap(), &[b"1".to_vec(), b"2".to_vec()]);
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

    #[test]
    fn value_validity() {
        assert!(valid_value(b"ok\ttab"));
        assert!(!valid_value(b"a\nb"));
        assert!(!valid_value(&[127]));
        assert!(!valid_value(&[0xff]));
        assert!(valid_value("ünï".as_bytes()));
    }
}
