//! Dense type identities: [`TyId`] indexes [`TyTable`], a struct of arrays of type constructors.
//!
//! Two checker types get the same id exactly when [`crate::types::lowering_key`] (or, for
//! [`TyTable::shape`], [`crate::types::type_key`]) would render the same text, but a lookup hashes
//! a few integers instead of rendering the tree. The table is append-only: lowering substitutes
//! new types as it goes, so ids are handed out on demand and never change.

use crate::types::{Kind, Name, Ty};
use std::hash::{Hash, Hasher};

/// The identity of an interned type: an index into a [`TyTable`].
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct TyId(u32);

impl TyId {
    /// The id as a vector index.
    pub fn index(self) -> usize {
        self.0 as usize
    }
}

/// A pool entry: a child id in the low bits, flags in the top two.
const VAR: u32 = 1 << 31;
const LIFTED: u32 = 1 << 30;
const CHILD: u32 = LIFTED - 1;
/// The child of a function type with no result yet.
const NO_RESULT: u32 = CHILD;
const EMPTY: u32 = u32::MAX;

/// Interned type constructors, one column per field.
#[derive(Default)]
pub struct TyTable {
    ids: Vec<Name>,
    kinds: Vec<Kind>,
    /// Start of each row's entries in `pool`: parameters, the result (functions only), arguments.
    starts: Vec<u32>,
    nparams: Vec<u32>,
    nargs: Vec<u32>,
    pool: Vec<u32>,
    /// Open-addressed slots holding a row index or `EMPTY`; length is a power of two.
    slots: Vec<u32>,
    /// The checker type that first produced each row.
    tys: Vec<Ty>,
    scratch: Vec<u32>,
}

#[derive(Default)]
struct Fx(u64);

impl Hasher for Fx {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.write_u64(b as u64);
        }
    }
    fn write_u32(&mut self, n: u32) {
        self.write_u64(n as u64);
    }
    fn write_u64(&mut self, n: u64) {
        self.0 = (self.0.rotate_left(5) ^ n).wrapping_mul(0x517c_c1b7_2722_0a95);
    }
}

fn kind_tag(k: Kind) -> u32 {
    k as u32
}

impl TyTable {
    /// An empty table.
    pub fn new() -> TyTable {
        TyTable::default()
    }

    /// The number of interned types.
    pub fn len(&self) -> usize {
        self.ids.len()
    }

    /// Whether nothing is interned yet.
    pub fn is_empty(&self) -> bool {
        self.ids.is_empty()
    }

    /// The checker type that first produced `id`.
    pub fn ty(&self, id: TyId) -> &Ty {
        &self.tys[id.index()]
    }

    /// The identity of `t`, including which function parameters are represented as optionals.
    pub fn intern(&mut self, t: &Ty) -> TyId {
        self.walk(t, true)
    }

    /// The identity of `t`'s structure alone, ignoring which parameters may be omitted.
    pub fn shape(&mut self, t: &Ty) -> TyId {
        self.walk(t, false)
    }

    fn walk(&mut self, t: &Ty, lifted: bool) -> TyId {
        let mark = self.scratch.len();
        let mut np = 0u32;
        if t.kind == Kind::Function {
            for p in &t.params {
                let child = self.walk(&p.ty, lifted).0;
                let mut e = child;
                if p.mutable {
                    e |= VAR;
                }
                if lifted && t.is_lifted(p.name) {
                    e |= LIFTED;
                }
                self.scratch.push(e);
                np += 1;
            }
            let r = match &t.result {
                Some(r) => self.walk(r, lifted).0,
                None => NO_RESULT,
            };
            self.scratch.push(r);
        }
        let mut na = 0u32;
        for a in &t.args {
            let child = self.walk(a, lifted).0;
            self.scratch.push(child);
            na += 1;
        }
        let id = self.find_or_add(t, mark, np, na);
        self.scratch.truncate(mark);
        id
    }

    fn hash_row(id: Name, kind: Kind, np: u32, na: u32, entries: &[u32]) -> u64 {
        let mut h = Fx::default();
        id.hash(&mut h);
        h.write_u32(kind_tag(kind));
        h.write_u32(np);
        h.write_u32(na);
        for &e in entries {
            h.write_u32(e);
        }
        h.finish()
    }

    fn row(&self, row: usize) -> &[u32] {
        let start = self.starts[row] as usize;
        let n = self.nparams[row] as usize + self.nargs[row] as usize;
        let result = usize::from(self.kinds[row] == Kind::Function);
        &self.pool[start..start + n + result]
    }

    fn find_or_add(&mut self, t: &Ty, mark: usize, np: u32, na: u32) -> TyId {
        if (self.ids.len() + 1) * 2 > self.slots.len() {
            self.grow();
        }
        let mask = self.slots.len() - 1;
        let entries = &self.scratch[mark..];
        let mut i = Self::hash_row(t.id, t.kind, np, na, entries) as usize & mask;
        loop {
            let slot = self.slots[i];
            if slot == EMPTY {
                break;
            }
            let r = slot as usize;
            if self.ids[r] == t.id
                && self.kinds[r] == t.kind
                && self.nparams[r] == np
                && self.nargs[r] == na
                && self.row(r) == entries
            {
                return TyId(slot);
            }
            i = (i + 1) & mask;
        }
        let row = self.ids.len() as u32;
        assert!(row < NO_RESULT, "type table full");
        self.ids.push(t.id);
        self.kinds.push(t.kind);
        self.starts.push(self.pool.len() as u32);
        self.nparams.push(np);
        self.nargs.push(na);
        self.pool.extend_from_slice(&self.scratch[mark..]);
        self.tys.push(t.clone());
        self.slots[i] = row;
        TyId(row)
    }

    fn grow(&mut self) {
        let cap = (self.slots.len() * 2).max(64);
        self.slots = vec![EMPTY; cap];
        let mask = cap - 1;
        for r in 0..self.ids.len() {
            let entries = self.row(r);
            let mut i = Self::hash_row(
                self.ids[r],
                self.kinds[r],
                self.nparams[r],
                self.nargs[r],
                entries,
            ) as usize
                & mask;
            while self.slots[i] != EMPTY {
                i = (i + 1) & mask;
            }
            self.slots[i] = r as u32;
        }
    }
}
