//! Interned identifiers.

use std::collections::HashMap;
use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::{Mutex, OnceLock};

/// The handle through which names are interned and read. Today every handle shares the process
/// table; callers hold one so the table can later belong to a session and be freed with it (see
/// `proposals/session-owned-interner.md`). Pass it down; do not reach for [`Names::global`] in new
/// code.
#[derive(Copy, Clone, Debug, Default)]
pub struct Names;

impl Names {
    /// The handle for the process table, for code not yet given one.
    pub const fn global() -> Names {
        Names
    }

    /// Interns `text`.
    pub fn intern(&self, text: &str) -> Symbol {
        Symbol::intern(text)
    }

    /// The text of `sym`, valid while this handle is.
    pub fn str(&self, sym: impl std::borrow::Borrow<Symbol>) -> &str {
        sym.borrow().as_str()
    }
}

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

/// An index into an [`Interner`]. Plain data: it compares, hashes and copies as a `u32`, and
/// means nothing without the interner that made it.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Sym(pub u32);

/// A session-owned string table: every name in one byte buffer, one end offset per name, and an
/// open-addressed slot array of ids. Interning hashes the text once and compares integers; the
/// table owns its memory, so dropping it frees every name. Id 0 is the empty string.
pub struct Interner {
    bytes: String,
    ends: Vec<u32>,
    slots: Vec<u32>,
}

fn hash_text(text: &str) -> u32 {
    // FNV-1a, folded to 32 bits.
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in text.bytes() {
        h = (h ^ u64::from(b)).wrapping_mul(0x100_0000_01b3);
    }
    (h ^ (h >> 32)) as u32
}

impl Default for Interner {
    fn default() -> Self {
        Self::new()
    }
}

impl Interner {
    /// An interner holding only the empty string.
    pub fn new() -> Interner {
        Interner {
            bytes: String::new(),
            ends: vec![0],
            slots: vec![0; 64],
        }
    }

    /// The number of interned strings, counting the empty string.
    pub fn len(&self) -> usize {
        self.ends.len()
    }

    /// Always false: the empty string is interned from the start.
    pub fn is_empty(&self) -> bool {
        false
    }

    /// Bytes of text held.
    pub fn text_bytes(&self) -> usize {
        self.bytes.len()
    }

    /// The text of `sym`. Panics on an id from another interner that is out of range.
    pub fn str(&self, sym: Sym) -> &str {
        let id = sym.0 as usize;
        let start = if id == 0 {
            0
        } else {
            self.ends[id - 1] as usize
        };
        &self.bytes[start..self.ends[id] as usize]
    }

    /// Interns `text`.
    pub fn intern(&mut self, text: &str) -> Sym {
        if text.is_empty() {
            return Sym(0);
        }
        let mask = self.slots.len() - 1;
        let mut at = hash_text(text) as usize & mask;
        loop {
            let id = self.slots[at];
            if id == 0 {
                break;
            }
            if self.str(Sym(id)) == text {
                return Sym(id);
            }
            at = (at + 1) & mask;
        }
        let id = self.ends.len() as u32;
        self.bytes.push_str(text);
        self.ends.push(self.bytes.len() as u32);
        self.slots[at] = id;
        if self.ends.len() * 2 > self.slots.len() {
            self.grow();
        }
        Sym(id)
    }

    fn grow(&mut self) {
        let mut slots = vec![0u32; self.slots.len() * 2];
        let mask = slots.len() - 1;
        for id in 1..self.ends.len() as u32 {
            let mut at = hash_text(self.str(Sym(id))) as usize & mask;
            while slots[at] != 0 {
                at = (at + 1) & mask;
            }
            slots[at] = id;
        }
        self.slots = slots;
    }
}

#[cfg(test)]
mod interner_tests {
    use super::*;

    #[test]
    fn equal_text_shares_an_id_and_round_trips() {
        let mut t = Interner::new();
        let a = t.intern("alpha");
        let b = t.intern("beta");
        assert_ne!(a, b);
        assert_eq!(t.intern("alpha"), a);
        assert_eq!((t.str(a), t.str(b)), ("alpha", "beta"));
        assert_eq!(t.intern(""), Sym(0));
        assert_eq!(t.str(Sym(0)), "");
    }

    #[test]
    fn survives_growth() {
        let mut t = Interner::new();
        let ids: Vec<Sym> = (0..5000).map(|i| t.intern(&format!("name{i}"))).collect();
        for (i, id) in ids.iter().enumerate() {
            assert_eq!(t.str(*id), format!("name{i}"));
            assert_eq!(t.intern(&format!("name{i}")), *id);
        }
        assert_eq!(t.len(), 5001);
    }

    #[test]
    fn dropping_frees_the_names() {
        // Two interners are independent: the same text gets ids from each, with no shared state.
        let mut a = Interner::new();
        let mut b = Interner::new();
        a.intern("x");
        assert_eq!(b.intern("y"), Sym(1));
        assert_eq!(a.str(Sym(1)), "x");
    }
}
