//! Machine layout of MIR types.
//!
//! A value is *flattened* into scalar leaves that live in registers; the same
//! leaves, laid out with natural alignment, are its memory representation (list
//! elements, boxed alternatives, stack slots handed to the runtime).
//!
//! | type | leaves |
//! | --- | --- |
//! | `Unit` | none |
//! | `Bool` | `i8` |
//! | `Int`, `Ptr`, closures, `Shared[T]` | `i64` |
//! | `Int8`, `Int16`, `Int32` | `i64` in registers, 1, 2, 4 bytes in memory |
//! | `UInt8`, `UInt16`, `UInt32` | `i64` in registers (zero-extended), 1, 2, 4 bytes in memory |
//! | `UInt64` | `i64` bit pattern |
//! | `Float` | `f64` |
//! | `Float32` | `f64` in registers, 4 bytes in memory |
//! | `String` | `ptr, tagged` (length and ownership tag, see `ms_rt_abi::StrVal`) |
//! | `List[T]`, `Bytes` | `ptr, len, cap` |
//! | `Map`, `Set` | seven `i64` words (`MapVal`) |
//! | record | the fields' leaves in declaration order |
//! | `T?` of a closure or handle object (single-pointer payloads) | nullable `i64` |
//! | `String?` | the string's leaves; none is a null `ptr` (tagged static, length 0) |
//! | `T?` otherwise | `present: i8`, then `T`'s leaves |
//! | `T?` that reaches itself by value | nullable `i64` pointer to a block of `T`'s leaves |
//! | alternative | `tag: i64`, then payload slots shared by all cases |
//! | recursive alternative | `i64` pointer to a heap block `{ tag, payload }` |
//! | interface | `data, vtable` |

use ms_mir::ir::{Boxing, Module};
use ms_mir::types::{AltId, Ty, TyKind};
use std::rc::Rc;

/// A scalar machine value.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Leaf {
    /// 64-bit integer or pointer.
    I64,
    /// 64-bit float.
    F64,
    /// Byte (booleans, presence flags).
    I8,
    /// `Int8`: an `i64` register, one byte in memory.
    N8,
    /// `Int16`: an `i64` register, two bytes in memory.
    N16,
    /// `Int32`: an `i64` register, four bytes in memory.
    N32,
    /// `UInt8`: an `i64` register holding the zero-extended value, one byte in memory.
    U8,
    /// `UInt16`: an `i64` register holding the zero-extended value, two bytes in memory.
    U16,
    /// `UInt32`: an `i64` register holding the zero-extended value, four bytes in memory.
    U32,
    /// `Float32`: an `f64` register, four bytes in memory.
    F32,
}

impl Leaf {
    /// Size and alignment in bytes.
    pub fn size(self) -> u32 {
        match self {
            Leaf::I8 | Leaf::N8 | Leaf::U8 => 1,
            Leaf::N16 | Leaf::U16 => 2,
            Leaf::N32 | Leaf::U32 | Leaf::F32 => 4,
            _ => 8,
        }
    }
}

/// How an alternative is represented.
#[derive(Clone, Debug)]
pub enum AltRepr {
    /// Tag and payload slots held directly in registers. `slots[c][i]` is the index
    /// into the full leaf list (tag is leaf 0) of case `c`'s `i`th leaf.
    Inline {
        /// Per case, per payload leaf: index into `leaves`.
        slots: Vec<Vec<usize>>,
    },
    /// A pointer to a block with the same memory layout as `Inline`.
    Boxed {
        /// Per case, per payload leaf: index into the block's leaves.
        slots: Vec<Vec<usize>>,
        /// Leaves of the block (tag first).
        block: Vec<Leaf>,
    },
}

/// The flattened shape of a type.
#[derive(Clone, Debug)]
pub struct Shape {
    /// Register leaves.
    pub leaves: Vec<Leaf>,
    /// Extra structure for alternatives.
    pub alt: Option<AltRepr>,
}

/// Memory layout of a sequence of leaves.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MemLayout {
    /// Byte offset of each leaf.
    pub offsets: Vec<u32>,
    /// Total size, rounded up to the alignment.
    pub size: u32,
    /// Alignment: the widest leaf, 1 for empty.
    pub align: u32,
}

/// Computes the memory layout of `leaves` with natural alignment.
pub fn mem_layout(leaves: &[Leaf]) -> MemLayout {
    let mut off = 0u32;
    let mut align = 1u32;
    let mut offsets = Vec::with_capacity(leaves.len());
    for l in leaves {
        let a = l.size();
        align = align.max(a);
        off = off.div_ceil(a) * a;
        offsets.push(off);
        off += a;
    }
    MemLayout {
        offsets,
        size: off.div_ceil(align) * align,
        align,
    }
}

/// Per case, per field: the field's type and its leaf indices into the alternative's leaf list.
pub type AltFields = Vec<Vec<(Ty, Vec<usize>)>>;

/// Layout tables for one module, built once from the immutable type table.
///
/// Struct of arrays addressed by `Ty` / `AltId` index: every shape is a `(start, len)` span into
/// one leaf pool, so lookups are array reads with no hashing, sharing, or interior mutability.
pub struct Layouts<'m> {
    /// The module whose types are described.
    pub m: &'m Module,
    /// Register leaves of every type, back to back.
    pool: Vec<Leaf>,
    /// Per `Ty`: `(start, len)` of its register leaves in `pool`.
    span: Vec<(u32, u32)>,
    /// Per `Ty`: index into `reprs`, or `NO_REPR`.
    repr_of: Vec<u32>,
    /// Representations of alternatives.
    reprs: Vec<Rc<AltRepr>>,
    /// Per `AltId`: the alternative lives behind a pointer.
    alt_boxed: Vec<bool>,
    /// Per inner `Ty`: `inner?` holds its payload behind a nullable pointer.
    opt_boxed: Vec<bool>,
    /// Per `AltId`: case fields with leaf indices.
    fields: Vec<Rc<AltFields>>,
}

const NO_REPR: u32 = u32::MAX;

#[derive(Clone, Copy, PartialEq)]
enum State {
    Todo,
    Active,
    Done,
}

impl<'m> Layouts<'m> {
    /// Builds the tables for every type of `m`.
    pub fn new(m: &'m Module) -> Self {
        let n = m.types.len();
        let mut boxing = Boxing::default();
        let alt_boxed = (0..m.alts.len())
            .map(|i| boxing.alt(m, AltId(i as u32)))
            .collect();
        let mut opt_boxed = vec![false; n];
        for i in 0..n {
            if let TyKind::Opt(inner) = m.types.kind(Ty(i as u32)) {
                opt_boxed[inner.index()] = boxing.opt(m, *inner);
            }
        }
        let mut lay = Layouts {
            m,
            pool: Vec::new(),
            span: vec![(0, 0); n],
            repr_of: vec![NO_REPR; n],
            reprs: Vec::new(),
            alt_boxed,
            opt_boxed,
            fields: vec![Rc::default(); m.alts.len()],
        };
        let mut state = vec![State::Todo; n];
        for i in 0..n {
            lay.build(Ty(i as u32), &mut state);
        }
        for i in 0..m.alts.len() {
            lay.fields[i] = Rc::new(lay.build_fields(AltId(i as u32)));
        }
        lay
    }

    /// Whether the alternative contains itself by value and therefore lives behind a pointer.
    pub fn is_boxed(&self, a: AltId) -> bool {
        self.alt_boxed[a.index()]
    }

    /// Whether `inner?` contains itself by value (`type Node: next: Node?`)
    /// and therefore holds its payload in a heap block behind a nullable pointer.
    pub fn opt_is_boxed(&self, inner: Ty) -> bool {
        self.opt_boxed[inner.index()]
    }

    /// Extra structure for alternatives: `None` for every other type.
    pub fn alt_repr(&self, ty: Ty) -> Option<&AltRepr> {
        self.reprs.get(self.repr_of[ty.index()] as usize).map(|r| &**r)
    }

    /// [`Self::alt_repr`] as a shared handle, for callers that keep it across mutation.
    pub fn alt_repr_rc(&self, ty: Ty) -> Option<Rc<AltRepr>> {
        self.reprs.get(self.repr_of[ty.index()] as usize).cloned()
    }

    /// Per-case, per-field `(type, leaf indices into the alt's leaf/block list)`.
    pub fn alt_fields(&self, a: AltId) -> Rc<AltFields> {
        self.fields[a.index()].clone()
    }

    /// The register leaves of `ty`.
    pub fn leaf_slice(&self, ty: Ty) -> &[Leaf] {
        let (start, len) = self.span[ty.index()];
        &self.pool[start as usize..(start + len) as usize]
    }

    /// The register leaves of `ty`.
    pub fn leaves(&self, ty: Ty) -> Vec<Leaf> {
        self.leaf_slice(ty).to_vec()
    }

    /// Number of register leaves.
    pub fn width(&self, ty: Ty) -> usize {
        self.span[ty.index()].1 as usize
    }

    /// Memory layout of `ty`.
    pub fn mem(&self, ty: Ty) -> MemLayout {
        mem_layout(self.leaf_slice(ty))
    }

    /// Whether `inner?` is a nullable pointer.
    pub fn opt_is_nullable(&self, inner: Ty) -> bool {
        self.opt_is_boxed(inner)
            || matches!(self.m.types.kind(inner), TyKind::Fn(..))
            || matches!(self.m.types.kind(inner), TyKind::Obj(n, _) if n != "Map" && n != "Set")
    }

    /// Whether values of `ty` have the string layout and drop and copy like a string: `String`,
    /// and `String?`, whose none is a static empty string with a null pointer.
    pub fn is_str_like(&self, ty: Ty) -> bool {
        match self.m.types.kind(ty) {
            TyKind::Str => true,
            TyKind::Opt(inner) => matches!(self.m.types.kind(*inner), TyKind::Str),
            _ => false,
        }
    }

    fn set(&mut self, ty: Ty, leaves: &[Leaf]) {
        self.span[ty.index()] = (self.pool.len() as u32, leaves.len() as u32);
        self.pool.extend_from_slice(leaves);
    }

    /// Fills the tables for `ty` after the types it contains by value.
    fn build(&mut self, ty: Ty, state: &mut [State]) {
        use Leaf::*;
        match state[ty.index()] {
            State::Done | State::Active => return,
            State::Todo => {}
        }
        state[ty.index()] = State::Active;
        let kind = self.m.types.kind(ty);
        let plain: Vec<Leaf> = match kind {
            TyKind::Unit => vec![],
            TyKind::Bool => vec![I8],
            TyKind::Int | TyKind::Ptr | TyKind::Fn(..) => vec![I64],
            TyKind::Int8 => vec![N8],
            TyKind::Int16 => vec![N16],
            TyKind::Int32 => vec![N32],
            TyKind::UInt8 => vec![U8],
            TyKind::UInt16 => vec![U16],
            TyKind::UInt32 => vec![U32],
            TyKind::UInt64 => vec![I64],
            TyKind::Float => vec![F64],
            TyKind::Float32 => vec![F32],
            TyKind::Str => vec![I64, I64],
            TyKind::Bytes | TyKind::List(_) => vec![I64, I64, I64],
            TyKind::Obj(n, _) if n == "Map" || n == "Set" => {
                vec![I64; ms_rt_abi::MAP_SIZE / 8]
            }
            TyKind::Obj(..) => vec![I64],
            TyKind::Iface(_) => vec![I64, I64],
            TyKind::Rec(r) => {
                let mut l = Vec::new();
                for f in &self.m.records[r.index()].fields {
                    self.build(f.1, state);
                    l.extend_from_slice(self.leaf_slice(f.1));
                }
                l
            }
            TyKind::Opt(inner) => {
                if self.opt_is_nullable(*inner) {
                    vec![I64]
                } else if self.is_str_like(ty) {
                    vec![I64, I64]
                } else {
                    self.build(*inner, state);
                    let mut l = vec![I8];
                    l.extend_from_slice(self.leaf_slice(*inner));
                    l
                }
            }
            TyKind::Alt(a) => {
                if self.is_boxed(*a) {
                    // One pointer; this also ends the recursion through its own fields.
                    self.set(ty, &[I64]);
                }
                self.build_alt(ty, *a, state);
                state[ty.index()] = State::Done;
                return;
            }
        };
        self.set(ty, &plain);
        state[ty.index()] = State::Done;
    }

    fn build_alt(&mut self, ty: Ty, a: AltId, state: &mut [State]) {
        use Leaf::*;
        let def = &self.m.alts[a.index()];
        let mut cases: Vec<Vec<Leaf>> = Vec::with_capacity(def.cases.len());
        for c in &def.cases {
            let mut l = Vec::new();
            for f in &c.fields {
                self.build(f.1, state);
                l.extend_from_slice(self.leaf_slice(f.1));
            }
            cases.push(l);
        }
        // Payload slots are shared per leaf kind, widest first so each stays aligned.
        const KINDS: [Leaf; 10] = [I64, F64, F32, N32, U32, N16, U16, N8, U8, I8];
        let count = |l: Leaf| {
            cases
                .iter()
                .map(|c| c.iter().filter(|x| **x == l).count())
                .max()
                .unwrap_or(0)
        };
        let mut block = vec![I64];
        let mut first = [0usize; 10];
        for (k, l) in KINDS.iter().enumerate() {
            first[k] = block.len();
            block.extend(std::iter::repeat_n(*l, count(*l)));
        }
        let slots: Vec<Vec<usize>> = cases
            .iter()
            .map(|c| {
                let mut next = first;
                c.iter()
                    .map(|l| {
                        let k = KINDS
                            .iter()
                            .position(|x| x == l)
                            .expect("payload leaf kind");
                        let i = next[k];
                        next[k] += 1;
                        i
                    })
                    .collect()
            })
            .collect();
        self.repr_of[ty.index()] = self.reprs.len() as u32;
        if self.is_boxed(a) {
            self.reprs.push(Rc::new(AltRepr::Boxed { slots, block }));
        } else {
            self.set(ty, &block);
            self.reprs.push(Rc::new(AltRepr::Inline { slots }));
        }
    }

    fn build_fields(&self, a: AltId) -> AltFields {
        let ty = self
            .m
            .types
            .find(&TyKind::Alt(a))
            .expect("alt type interned");
        let no_slots = Vec::new();
        let slots = match self.alt_repr(ty) {
            Some(AltRepr::Inline { slots }) | Some(AltRepr::Boxed { slots, .. }) => slots,
            None => &no_slots,
        };
        self.m.alts[a.index()]
            .cases
            .iter()
            .zip(slots)
            .map(|(c, sl)| {
                let mut at = 0;
                c.fields
                    .iter()
                    .map(|f| {
                        let w = self.width(f.1);
                        let idx = sl[at..at + w].to_vec();
                        at += w;
                        (f.1, idx)
                    })
                    .collect()
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn optional_string_is_as_wide_as_a_string() {
        let mut m = Module::new("t");
        let os = m.types.opt(Ty::STR);
        let oi = m.types.opt(Ty::INT);
        let lay = Layouts::new(&m);
        assert_eq!(lay.mem(os).size, ms_rt_abi::OPT_STR_SIZE as u32);
        assert_eq!(lay.leaves(os), lay.leaves(Ty::STR));
        assert!(lay.is_str_like(os) && lay.is_str_like(Ty::STR) && !lay.is_str_like(oi));
    }
}
