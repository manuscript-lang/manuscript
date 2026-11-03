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
