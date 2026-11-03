//! Interned identifiers.

use std::collections::HashMap;
use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::{Mutex, OnceLock};

/// An interned string. Equal strings intern to the same `Symbol`, so equality
/// and hashing are pointer operations and `as_str` is free. Symbols are
/// process-wide (the table is shared by all threads and never shrinks). Each symbol carries its
/// intern order, which equality and hashing use, so hash-map iteration order does not depend on
/// where the allocator placed a string.
#[derive(Copy, Clone)]
pub struct Symbol(u32, &'static str);

fn table() -> &'static Mutex<HashMap<&'static str, Symbol>> {
    static TABLE: OnceLock<Mutex<HashMap<&'static str, Symbol>>> = OnceLock::new();
    TABLE.get_or_init(|| Mutex::new(HashMap::with_capacity(4096)))
}

impl Symbol {
    /// Interns `text`.
    pub fn intern(text: &str) -> Symbol {
        if text.is_empty() {
            return Symbol(0, "");
        }
        let mut map = table().lock().unwrap_or_else(|e| e.into_inner());
        if let Some(found) = map.get(text) {
            return *found;
        }
        let leaked: &'static str = Box::leak(text.to_owned().into_boxed_str());
        let symbol = Symbol(map.len() as u32 + 1, leaked);
        map.insert(leaked, symbol);
        symbol
    }

    /// The interned text.
    pub fn as_str(self) -> &'static str {
        self.1
    }
}

impl PartialEq for Symbol {
    fn eq(&self, other: &Symbol) -> bool {
        self.0 == other.0
    }
}
impl Eq for Symbol {}
impl Hash for Symbol {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.0.hash(state);
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
        self.1.cmp(other.1)
    }
}
impl fmt::Debug for Symbol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self.1)
    }
}
impl fmt::Display for Symbol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.1)
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
        self.1
    }
}
impl PartialEq<str> for Symbol {
    fn eq(&self, other: &str) -> bool {
        self.1 == other
    }
}
impl PartialEq<&str> for Symbol {
    fn eq(&self, other: &&str) -> bool {
        self.1 == *other
    }
}
