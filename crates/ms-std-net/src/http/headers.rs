//! `HttpHeaders`: an ordered multimap of names to byte values.

use crate::error::HttpErr;
use std::cell::RefCell;
use std::rc::Rc;

/// A headers collection shared between handles (`HttpHeaders` values alias).
pub type Shared = Rc<RefCell<Headers>>;

/// One name with its values. Names compare with ASCII case folding and keep the
/// spelling of their first use.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub values: Vec<Vec<u8>>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Headers {
    entries: Vec<Entry>,
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
            Some(i) => self.entries[i].values.push(value),
            None => self.entries.push(Entry {
                name: name.to_string(),
                values: vec![value],
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
        self.position(name)
            .map(|i| self.entries[i].values.as_slice())
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
                self.entries.remove(i);
                true
            }
            None => false,
        }
    }

    /// Replaces every value of `name` with `value`.
    pub fn set(&mut self, name: &str, value: Vec<u8>) {
        match self.position(name) {
            Some(i) => self.entries[i].values = vec![value],
            None => self.add(name, value),
        }
    }

    /// Received headers as handlers see them: canonical names, sorted
    /// by name, values in arrival order.
    pub fn from_received(fields: impl IntoIterator<Item = (String, Vec<u8>)>) -> Headers {
        let mut sorted: Vec<(String, Vec<Vec<u8>>)> = Vec::new();
        for (name, value) in fields {
            let key = canonical_owned(name);
            match sorted.iter_mut().find(|(k, _)| *k == key) {
                Some((_, values)) => values.push(value),
                None => sorted.push((key, vec![value])),
            }
        }
        sorted.sort_by(|a, b| a.0.cmp(&b.0));
        Headers {
            entries: sorted
                .into_iter()
                .map(|(name, values)| Entry { name, values })
                .collect(),
        }
    }

    /// Whether every name and value is UTF-8.
    pub fn is_text(&self) -> bool {
        self.entries
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
    fn value_validity() {
        assert!(valid_value(b"ok\ttab"));
        assert!(!valid_value(b"a\nb"));
        assert!(!valid_value(&[127]));
        assert!(!valid_value(&[0xff]));
        assert!(valid_value("ünï".as_bytes()));
    }
}
