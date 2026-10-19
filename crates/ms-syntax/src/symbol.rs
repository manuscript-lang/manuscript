//! Interned identifiers.

use std::collections::HashSet;
use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::{Mutex, OnceLock};

/// An interned string. Equal strings intern to the same `Symbol`, so equality
/// and hashing are pointer operations and `as_str` is free. Symbols are
/// process-wide (the table is shared by all threads and never shrinks).
#[derive(Copy, Clone)]
pub struct Symbol(&'static str);

fn table() -> &'static Mutex<HashSet<&'static str>> {
    static TABLE: OnceLock<Mutex<HashSet<&'static str>>> = OnceLock::new();
    TABLE.get_or_init(|| Mutex::new(HashSet::with_capacity(4096)))
}

impl Symbol {
    /// Interns `text`.
    pub fn intern(text: &str) -> Symbol {
        if text.is_empty() {
            return Symbol("");
        }
        let mut set = table().lock().unwrap_or_else(|e| e.into_inner());
        if let Some(found) = set.get(text) {
            return Symbol(found);
        }
        let leaked: &'static str = Box::leak(text.to_owned().into_boxed_str());
        set.insert(leaked);
        Symbol(leaked)
    }

    /// The interned text.
    pub fn as_str(self) -> &'static str {
        self.0
    }
}

impl PartialEq for Symbol {
    fn eq(&self, other: &Symbol) -> bool {
        std::ptr::eq(self.0.as_ptr(), other.0.as_ptr()) && self.0.len() == other.0.len()
    }
}
impl Eq for Symbol {}
impl Hash for Symbol {
    fn hash<H: Hasher>(&self, state: &mut H) {
        (self.0.as_ptr() as usize).hash(state);
    }
}
impl PartialOrd for Symbol {
    fn partial_cmp(&self, other: &Symbol) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for Symbol {
    /// Orders by text, so sorted output is deterministic.
    fn cmp(&self, other: &Symbol) -> std::cmp::Ordering {
        self.0.cmp(other.0)
    }
}
impl fmt::Debug for Symbol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self.0)
    }
}
impl fmt::Display for Symbol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.0)
    }
}
impl From<&str> for Symbol {
    fn from(text: &str) -> Symbol {
        Symbol::intern(text)
    }
}
impl std::ops::Deref for Symbol {
    type Target = str;
    fn deref(&self) -> &str {
        self.0
    }
}
impl PartialEq<str> for Symbol {
    fn eq(&self, other: &str) -> bool {
        self.0 == other
    }
}
impl PartialEq<&str> for Symbol {
    fn eq(&self, other: &&str) -> bool {
        self.0 == *other
    }
}
