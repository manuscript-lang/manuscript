//! `HttpHeaders`: an ordered multimap of names to byte values.

use crate::error::HttpErr;
use std::cell::{Cell, OnceCell, RefCell};
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

pub struct Headers {
    /// This handle's table, shared until written, so handing the received headers to a handler
    /// copies nothing. Unset while the handle still reads the received fields' table.
    entries: OnceCell<Arc<Vec<Entry>>>,
    /// The received fields and the table built from them, shared by every handle copied from
    /// this one: the table is built when any of them first looks, so a request whose handler
    /// never looks at its headers never builds it.
    received: Option<Rc<Received>>,
}

/// A received field: its name as sent and its value.
type Field = (String, Vec<u8>);

struct Received {
    fields: Cell<Option<Vec<Field>>>,
    empty: bool,
    table: OnceCell<Arc<Vec<Entry>>>,
}

thread_local! {
    /// The entries of every empty `Headers` on this thread, so creating one allocates nothing.
    static EMPTY: Arc<Vec<Entry>> = Arc::new(Vec::new());
}

impl Default for Headers {
    fn default() -> Headers {
        Headers {
            entries: OnceCell::from(EMPTY.with(Arc::clone)),
            received: None,
        }
    }
}

impl Clone for Headers {
    fn clone(&self) -> Headers {
        Headers {
            entries: self.entries.clone(),
            received: self.received.clone(),
        }
    }
}

impl PartialEq for Headers {
    fn eq(&self, other: &Headers) -> bool {
        self.table() == other.table()
    }
}

impl Eq for Headers {}

impl std::fmt::Debug for Headers {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Headers")
            .field("entries", self.table())
            .finish()
    }
}

/// Token characters of RFC 9110.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b))
}

/// Outgoing values are UTF-8 text with no control bytes besides tab, and no DEL.
pub fn valid_value(value: &[u8]) -> bool {
    std::str::from_utf8(value).is_ok() && value.iter().all(|&b| (b >= 32 || b == b'\t') && b != 127)
}

/// `textproto.CanonicalMIMEHeaderKey`: keys with a space or non-token byte are
/// returned as they are.
pub fn canonical(name: &str) -> String {
    canonical_owned(name.to_string())
}

/// `canonical` over an owned name, edited in place.
pub fn canonical_owned(name: String) -> String {
    if !name
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b))
        || name.is_empty()
    {
        return name;
    }
    let mut upper = true;
    let mut bytes = name.into_bytes();
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

    /// The entries, built from the received fields on first use.
    fn table(&self) -> &Arc<Vec<Entry>> {
        self.entries.get_or_init(|| match &self.received {
            Some(received) => received
                .table
                .get_or_init(|| {
                    let fields = received.fields.take().unwrap_or_default();
                    Arc::new(Headers::build(fields))
                })
                .clone(),
            None => EMPTY.with(Arc::clone),
        })
    }

    /// The entries to change; a pending table is built first.
    fn table_mut(&mut self) -> &mut Arc<Vec<Entry>> {
        self.table();
        self.entries.get_mut().expect("table built above")
    }

    pub fn entries(&self) -> &[Entry] {
        self.table()
    }

    pub fn is_empty(&self) -> bool {
        match (self.entries.get(), &self.received) {
            (Some(entries), _) => entries.is_empty(),
            (None, Some(received)) => received.empty,
            (None, None) => true,
        }
    }

    fn position(&self, name: &str) -> Option<usize> {
        self.table()
            .iter()
            .position(|e| e.name.eq_ignore_ascii_case(name))
    }

    /// Adds a value under `name` without validating it.
    pub fn add(&mut self, name: &str, value: Vec<u8>) {
        match self.position(name) {
            Some(i) => Arc::make_mut(self.table_mut())[i].values.push(value),
            None => Arc::make_mut(self.table_mut()).push(Entry {
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
        self.position(name).map(|i| &*self.table()[i].values)
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
        self.table().iter().map(|e| e.name.as_str()).collect()
    }

    pub fn remove(&mut self, name: &str) -> bool {
        match self.position(name) {
            Some(i) => {
                Arc::make_mut(self.table_mut()).remove(i);
                true
            }
            None => false,
        }
    }

    /// Replaces every value of `name` with `value`.
    pub fn set(&mut self, name: &str, value: Vec<u8>) {
        match self.position(name) {
            Some(i) => Arc::make_mut(self.table_mut())[i].values = Values::One(value),
            None => self.add(name, value),
        }
    }

    /// Received headers as handlers see them: canonical names, sorted
    /// by name, values in arrival order.
    pub fn from_received(fields: impl IntoIterator<Item = (String, Vec<u8>)>) -> Headers {
        Headers {
            entries: OnceCell::from(Arc::new(Headers::build(fields))),
            received: None,
        }
    }

    /// Like [`Headers::from_received`], but the table is built when first looked at.
    pub fn received_later(fields: Vec<(String, Vec<u8>)>) -> Headers {
        Headers {
            entries: OnceCell::new(),
            received: Some(Rc::new(Received {
                empty: fields.is_empty(),
                fields: Cell::new(Some(fields)),
                table: OnceCell::new(),
            })),
        }
    }

    fn build(fields: impl IntoIterator<Item = (String, Vec<u8>)>) -> Vec<Entry> {
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
        entries
    }

    /// Whether every name and value is UTF-8.
    pub fn is_text(&self) -> bool {
        self.table()
            .iter()
            .all(|e| e.values.iter().all(|v| std::str::from_utf8(v).is_ok()))
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

    #[test]
    fn a_lazily_received_table_matches_the_eager_one_and_copies_stay_apart() {
        let fields = || {
            vec![
                ("x-b".to_string(), b"1".to_vec()),
                ("ACCEPT".to_string(), b"a".to_vec()),
                ("X-B".to_string(), b"2".to_vec()),
            ]
        };
        let eager = Headers::from_received(fields());
        let lazy = Headers::received_later(fields());
        assert!(!lazy.is_empty());
        assert!(Headers::received_later(Vec::new()).is_empty());
        let mut copy = lazy.clone();
        assert_eq!(copy, eager);
        copy.append("New", b"v").unwrap();
        copy.remove("accept");
        assert_eq!(lazy, eager);
        assert_eq!(lazy.names(), vec!["Accept", "X-B"]);
        assert_eq!(copy.names(), vec!["X-B", "New"]);
        // A copy taken before anything looked still sees the received fields.
        let second = lazy.clone();
        assert_eq!(
            second.values("x-b").unwrap(),
            &[b"1".to_vec(), b"2".to_vec()]
        );
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
