//! Dense per-function tables keyed by [`Value`].
//!
//! A [`Value`] is an index into `Func::values`, so a pass keeps its facts in a `Vec` slot per value
//! instead of hashing: a lookup is one bounds check, a scan walks a dense entry vector
//! (deterministic), and nothing is hashed or rehashed. The index grows on demand to the largest key
//! inserted, so a table that holds a few small keys stays small.

use crate::ir::Value;
use std::ops::Index;

/// A map from [`Value`] to `T`: a `u32` slot per value index pointing into a dense entry vector,
/// so the index costs four bytes per value however large `T` is and iteration scans only entries.
#[derive(Clone, Debug)]
pub struct ValueMap<T> {
    /// Entry position plus one for each value index; zero when absent.
    slot: Vec<u32>,
    items: Vec<(Value, T)>,
}

impl<T> Default for ValueMap<T> {
    fn default() -> Self {
        ValueMap {
            slot: Vec::new(),
            items: Vec::new(),
        }
    }
}

impl<T> ValueMap<T> {
    /// An empty map.
    pub fn new() -> Self {
        Self::default()
    }

    fn pos(&self, k: &Value) -> Option<usize> {
        match self.slot.get(k.index()) {
            Some(&p) if p != 0 => Some(p as usize - 1),
            _ => None,
        }
    }

    /// The value for `k`.
    pub fn get(&self, k: &Value) -> Option<&T> {
        self.pos(k).map(|p| &self.items[p].1)
    }

    /// The value for `k`, mutably.
    pub fn get_mut(&mut self, k: &Value) -> Option<&mut T> {
        self.pos(k).map(|p| &mut self.items[p].1)
    }

    /// Whether `k` has an entry.
    pub fn contains_key(&self, k: &Value) -> bool {
        self.pos(k).is_some()
    }

    /// Sets `k`, returning the previous value.
    pub fn insert(&mut self, k: Value, v: T) -> Option<T> {
        if let Some(p) = self.pos(&k) {
            return Some(std::mem::replace(&mut self.items[p].1, v));
        }
        let i = k.index();
        if i >= self.slot.len() {
            self.slot.resize(i + 1, 0);
        }
        self.items.push((k, v));
        self.slot[i] = self.items.len() as u32;
        None
    }

    /// Removes `k`, returning its value.
    pub fn remove(&mut self, k: &Value) -> Option<T> {
        let p = self.pos(k)?;
        self.slot[k.index()] = 0;
        let (_, v) = self.items.swap_remove(p);
        if let Some((moved, _)) = self.items.get(p) {
            self.slot[moved.index()] = p as u32 + 1;
        }
        Some(v)
    }

    /// The value for `k`, inserting `make()` first when absent.
    pub fn get_or_insert_with(&mut self, k: Value, make: impl FnOnce() -> T) -> &mut T {
        let p = match self.pos(&k) {
            Some(p) => p,
            None => {
                self.insert(k, make());
                self.items.len() - 1
            }
        };
        &mut self.items[p].1
    }

    /// The number of entries.
    pub fn len(&self) -> usize {
        self.items.len()
    }

    /// Whether there are no entries.
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    /// Entries in insertion order (changed by removals).
    pub fn iter(&self) -> impl Iterator<Item = (&Value, &T)> {
        self.items.iter().map(|(k, v)| (k, v))
    }

    /// Keys in the same order as [`ValueMap::iter`].
    pub fn keys(&self) -> impl Iterator<Item = &Value> {
        self.items.iter().map(|(k, _)| k)
    }

    /// Keeps entries for which `keep` is true.
    pub fn retain(&mut self, mut keep: impl FnMut(&Value, &mut T) -> bool) {
        let mut items = std::mem::take(&mut self.items);
        items.retain_mut(|(k, v)| {
            let kept = keep(k, v);
            if !kept {
                self.slot[k.index()] = 0;
            }
            kept
        });
        for (p, (k, _)) in items.iter().enumerate() {
            self.slot[k.index()] = p as u32 + 1;
        }
        self.items = items;
    }
}

impl<T: Default> ValueMap<T> {
    /// The value for `k`, inserting the default when absent.
    pub fn get_or_default(&mut self, k: Value) -> &mut T {
        self.get_or_insert_with(k, T::default)
    }
}

impl<T> Index<&Value> for ValueMap<T> {
    type Output = T;
    fn index(&self, k: &Value) -> &T {
        self.get(k).expect("no entry for value")
    }
}

impl<T> FromIterator<(Value, T)> for ValueMap<T> {
    fn from_iter<I: IntoIterator<Item = (Value, T)>>(it: I) -> Self {
        let mut m = ValueMap::new();
        for (k, v) in it {
            m.insert(k, v);
        }
        m
    }
}

/// A set of [`Value`]s stored as a bitset.
#[derive(Clone, Debug, Default)]
pub struct ValueSet {
    words: Vec<u64>,
    len: usize,
}

impl ValueSet {
    /// An empty set.
    pub fn new() -> Self {
        Self::default()
    }

    /// Whether `v` is in the set.
    pub fn contains(&self, v: &Value) -> bool {
        let i = v.index();
        self.words
            .get(i >> 6)
            .is_some_and(|w| w >> (i & 63) & 1 != 0)
    }

    /// Adds `v`; true when it was absent.
    pub fn insert(&mut self, v: Value) -> bool {
        let i = v.index();
        if i >> 6 >= self.words.len() {
            self.words.resize((i >> 6) + 1, 0);
        }
        let bit = 1u64 << (i & 63);
        let fresh = self.words[i >> 6] & bit == 0;
        self.words[i >> 6] |= bit;
        self.len += usize::from(fresh);
        fresh
    }

    /// Removes `v`; true when it was present.
    pub fn remove(&mut self, v: &Value) -> bool {
        let i = v.index();
        let Some(w) = self.words.get_mut(i >> 6) else {
            return false;
        };
        let bit = 1u64 << (i & 63);
        let had = *w & bit != 0;
        *w &= !bit;
        self.len -= usize::from(had);
        had
    }

    /// The number of members.
    pub fn len(&self) -> usize {
        self.len
    }

    /// Whether the set is empty.
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Members in ascending order.
    pub fn iter(&self) -> impl Iterator<Item = Value> + '_ {
        self.words.iter().enumerate().flat_map(|(wi, &w)| {
            let mut bits = w;
            std::iter::from_fn(move || {
                if bits == 0 {
                    return None;
                }
                let b = bits.trailing_zeros();
                bits &= bits - 1;
                Some(Value((wi as u32) << 6 | b))
            })
        })
    }
}

impl FromIterator<Value> for ValueSet {
    fn from_iter<I: IntoIterator<Item = Value>>(it: I) -> Self {
        let mut s = ValueSet::new();
        s.extend(it);
        s
    }
}

impl Extend<Value> for ValueSet {
    fn extend<I: IntoIterator<Item = Value>>(&mut self, it: I) {
        for v in it {
            self.insert(v);
        }
    }
}

/// A multiplicative hasher for small integer keys (`rustc-hash`'s mix): the default SipHash costs
/// more than the table lookup it feeds.
#[derive(Default)]
struct Fx(u64);

impl std::hash::Hasher for Fx {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.write_u64(u64::from(b));
        }
    }
    fn write_u8(&mut self, n: u8) {
        self.write_u64(u64::from(n));
    }
    fn write_u16(&mut self, n: u16) {
        self.write_u64(u64::from(n));
    }
    fn write_u32(&mut self, n: u32) {
        self.write_u64(u64::from(n));
    }
    fn write_i64(&mut self, n: i64) {
        self.write_u64(n as u64);
    }
    fn write_usize(&mut self, n: usize) {
        self.write_u64(n as u64);
    }
    fn write_u64(&mut self, n: u64) {
        self.0 = (self.0.rotate_left(5) ^ n).wrapping_mul(0x517c_c1b7_2722_0a95);
    }
}

/// An expression table for value numbering over a dominator tree: entries are added on entering a
/// block and dropped, newest first, on leaving it ([`ScopedTable::mark`], [`ScopedTable::reset`]).
/// Entries and their operand lists live in two flat vectors and buckets are `u32` indices into the
/// entry vector, so a lookup hashes once, allocates nothing and removal is a truncation.
pub struct ScopedTable<K: Copy + Eq + std::hash::Hash> {
    /// Bucket to the newest entry plus one; zero when empty.
    heads: Vec<u32>,
    entries: Vec<ScopedEntry<K>>,
    operands: Vec<Value>,
    mask: usize,
}

struct ScopedEntry<K> {
    hash: u64,
    key: K,
    operands: (u32, u32),
    value: Value,
    /// The previous entry of the bucket plus one.
    next: u32,
}

impl<K: Copy + Eq + std::hash::Hash> ScopedTable<K> {
    /// A table for about `expected` live entries.
    pub fn new(expected: usize) -> Self {
        let size = (expected * 2).next_power_of_two().max(16);
        ScopedTable {
            heads: vec![0; size],
            entries: Vec::new(),
            operands: Vec::new(),
            mask: size - 1,
        }
    }

    fn hash(key: &K, operands: &[Value]) -> u64 {
        use std::hash::Hasher;
        let mut h = Fx::default();
        key.hash(&mut h);
        for v in operands {
            h.write_u32(v.0);
        }
        // Spread the multiplicative mix into the low bits the mask keeps.
        h.finish() ^ (h.finish() >> 29)
    }

    /// The value recorded for `key` over `operands`.
    pub fn get(&self, key: &K, operands: &[Value]) -> Option<Value> {
        let hash = Self::hash(key, operands);
        let mut at = self.heads[hash as usize & self.mask];
        while at != 0 {
            let e = &self.entries[at as usize - 1];
            if e.hash == hash
                && e.key == *key
                && self.operands[e.operands.0 as usize..e.operands.1 as usize] == *operands
            {
                return Some(e.value);
            }
            at = e.next;
        }
        None
    }

    /// Records `value` for `key` over `operands`; the caller has checked there is none.
    pub fn insert(&mut self, key: K, operands: &[Value], value: Value) {
        let hash = Self::hash(&key, operands);
        let start = self.operands.len() as u32;
        self.operands.extend_from_slice(operands);
        let bucket = hash as usize & self.mask;
        self.entries.push(ScopedEntry {
            hash,
            key,
            operands: (start, self.operands.len() as u32),
            value,
            next: self.heads[bucket],
        });
        self.heads[bucket] = self.entries.len() as u32;
    }

    /// The position to [`ScopedTable::reset`] to.
    pub fn mark(&self) -> usize {
        self.entries.len()
    }

    /// Drops every entry added since `mark`.
    pub fn reset(&mut self, mark: usize) {
        while self.entries.len() > mark {
            let e = self.entries.pop().expect("entry above the mark");
            self.heads[e.hash as usize & self.mask] = e.next;
            self.operands.truncate(e.operands.0 as usize);
        }
    }
}

#[cfg(test)]
mod scoped_table_tests {
    use super::*;

    #[test]
    fn entries_are_found_by_key_and_operands_and_leave_with_their_scope() {
        let mut t: ScopedTable<(u8, u8)> = ScopedTable::new(4);
        let (a, b, c) = (Value(1), Value(2), Value(3));
        t.insert((1, 0), &[a, b], c);
        let mark = t.mark();
        t.insert((1, 0), &[b, a], a);
        t.insert((2, 0), &[a, b], b);
        assert_eq!(t.get(&(1, 0), &[a, b]), Some(c));
        assert_eq!(t.get(&(1, 0), &[b, a]), Some(a));
        assert_eq!(t.get(&(2, 0), &[a, b]), Some(b));
        assert_eq!(t.get(&(1, 0), &[a]), None);
        t.reset(mark);
        assert_eq!(t.get(&(1, 0), &[a, b]), Some(c));
        assert_eq!(t.get(&(1, 0), &[b, a]), None);
        assert_eq!(t.get(&(2, 0), &[a, b]), None);
    }
}
