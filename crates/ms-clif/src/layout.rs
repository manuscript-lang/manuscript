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
//! | `Float` | `f64` |
//! | `Float32` | `f64` in registers, 4 bytes in memory |
//! | `String` | `ptr, tagged` (length and ownership tag, see `ms_rt_abi::StrVal`) |
//! | `List[T]`, `Bytes` | `ptr, len, cap` |
//! | `Map`, `Set` | seven `i64` words (`MapVal`) |
//! | record | the fields' leaves in declaration order |
//! | `Optional[T]` of a closure or handle object (single-pointer payloads) | nullable `i64` |
//! | `Optional[String]` | the string's leaves; none is a null `ptr` (tagged static, length 0) |
//! | `Optional[T]` otherwise | `present: i8`, then `T`'s leaves |
//! | `Optional[T]` that reaches itself by value | nullable `i64` pointer to a block of `T`'s leaves |
//! | alternative | `tag: i64`, then payload slots shared by all cases |
//! | recursive alternative | `i64` pointer to a heap block `{ tag, payload }` |
//! | interface | `data, vtable` |

use ms_mir::ir::{Boxing, Module};
use ms_mir::types::{AltId, Ty, TyKind};
use std::cell::RefCell;
use std::collections::HashMap;
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
    /// `Float32`: an `f64` register, four bytes in memory.
    F32,
}

impl Leaf {
    /// Size and alignment in bytes.
    pub fn size(self) -> u32 {
        match self {
            Leaf::I8 | Leaf::N8 => 1,
            Leaf::N16 => 2,
            Leaf::N32 | Leaf::F32 => 4,
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

/// Layout oracle for one module.
pub struct Layouts<'m> {
    /// The module whose types are described.
    pub m: &'m Module,
    cache: RefCell<HashMap<Ty, Rc<Shape>>>,
    alt_cache: RefCell<HashMap<AltId, Rc<AltFields>>>,
    boxing: RefCell<Boxing>,
}

/// Per case, per field: the field's type and its leaf indices into the alternative's leaf list.
pub type AltFields = Vec<Vec<(Ty, Vec<usize>)>>;

impl<'m> Layouts<'m> {
    /// A fresh oracle.
    pub fn new(m: &'m Module) -> Self {
        Layouts {
            m,
            cache: RefCell::new(HashMap::new()),
            alt_cache: RefCell::new(HashMap::new()),
            boxing: RefCell::new(Boxing::default()),
        }
    }

    /// Whether the alternative contains itself by value and therefore lives behind a pointer.
    pub fn is_boxed(&self, a: AltId) -> bool {
        self.boxing.borrow_mut().alt(self.m, a)
    }

    /// Whether `Optional[inner]` contains itself by value (`type Node: next: Optional[Node]`)
    /// and therefore holds its payload in a heap block behind a nullable pointer.
    pub fn opt_is_boxed(&self, inner: Ty) -> bool {
        self.boxing.borrow_mut().opt(self.m, inner)
    }

    /// The flattened shape of `ty`.
    ///
    /// Shared: every instruction asks, and copying the leaves and case slots of a large
    /// alternative each time made lowering quadratic in its case count.
    pub fn shape(&self, ty: Ty) -> Rc<Shape> {
        if let Some(s) = self.cache.borrow().get(&ty) {
            return s.clone();
        }
        if let TyKind::Alt(a) = self.m.types.kind(ty)
            && self.is_boxed(*a)
        {
            // A boxed alternative is one pointer; this also ends the recursion through its own fields.
            self.cache.borrow_mut().insert(
                ty,
                Rc::new(Shape {
                    leaves: vec![Leaf::I64],
                    alt: None,
                }),
            );
        }
        let s = Rc::new(self.compute(ty));
        self.cache.borrow_mut().insert(ty, s.clone());
        s
    }

    /// Per-case, per-field `(type, leaf indices into the alt's leaf/block list)`.
    pub fn alt_fields(&self, a: AltId) -> Rc<AltFields> {
        if let Some(f) = self.alt_cache.borrow().get(&a) {
            return f.clone();
        }
        let ty = self
            .m
            .types
            .find(&TyKind::Alt(a))
            .expect("alt type interned");
        let shape = self.shape(ty);
        let no_slots = Vec::new();
        let slots = match &shape.alt {
            Some(AltRepr::Inline { slots }) | Some(AltRepr::Boxed { slots, .. }) => slots,
            None => &no_slots,
        };
        let fields: AltFields = self.m.alts[a.index()]
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
            .collect();
        let fields = Rc::new(fields);
        self.alt_cache.borrow_mut().insert(a, fields.clone());
        fields
    }

    /// The register leaves of `ty`.
    pub fn leaves(&self, ty: Ty) -> Vec<Leaf> {
        self.shape(ty).leaves.clone()
    }

    /// Number of register leaves.
    pub fn width(&self, ty: Ty) -> usize {
        self.shape(ty).leaves.len()
    }

    /// Memory layout of `ty`.
    pub fn mem(&self, ty: Ty) -> MemLayout {
        mem_layout(&self.shape(ty).leaves)
    }

    /// Whether `Optional[inner]` is a nullable pointer.
    pub fn opt_is_nullable(&self, inner: Ty) -> bool {
        self.opt_is_boxed(inner)
            || matches!(self.m.types.kind(inner), TyKind::Fn(..))
            || matches!(self.m.types.kind(inner), TyKind::Obj(n, _) if n != "Map" && n != "Set")
    }

    /// Whether values of `ty` have the string layout and drop and copy like a string: `String`,
    /// and `Optional[String]`, whose none is a static empty string with a null pointer.
    pub fn is_str_like(&self, ty: Ty) -> bool {
        match self.m.types.kind(ty) {
            TyKind::Str => true,
            TyKind::Opt(inner) => matches!(self.m.types.kind(*inner), TyKind::Str),
            _ => false,
        }
    }

    fn compute(&self, ty: Ty) -> Shape {
        use Leaf::*;
        let plain = |leaves: Vec<Leaf>| Shape { leaves, alt: None };
        match self.m.types.kind(ty) {
            TyKind::Unit => plain(vec![]),
            TyKind::Bool => plain(vec![I8]),
            TyKind::Int | TyKind::Ptr | TyKind::Fn(..) => plain(vec![I64]),
            TyKind::Int8 => plain(vec![N8]),
            TyKind::Int16 => plain(vec![N16]),
            TyKind::Int32 => plain(vec![N32]),
            TyKind::Float => plain(vec![F64]),
            TyKind::Float32 => plain(vec![F32]),
            TyKind::Str => plain(vec![I64, I64]),
            TyKind::Bytes | TyKind::List(_) => plain(vec![I64, I64, I64]),
            TyKind::Obj(n, _) if n == "Map" || n == "Set" => {
                plain(vec![I64; ms_rt_abi::MAP_SIZE / 8])
            }
            TyKind::Obj(..) => plain(vec![I64]),
            TyKind::Iface(_) => plain(vec![I64, I64]),
            TyKind::Rec(r) => plain(
                self.m.records[r.index()]
                    .fields
                    .iter()
                    .flat_map(|f| self.leaves(f.1))
                    .collect(),
            ),
            TyKind::Opt(inner) => {
                if self.opt_is_nullable(*inner) {
                    plain(vec![I64])
                } else if self.is_str_like(ty) {
                    plain(vec![I64, I64])
                } else {
                    let mut l = vec![I8];
                    l.extend(self.leaves(*inner));
                    plain(l)
                }
            }
            TyKind::Alt(a) => self.alt_shape(*a),
        }
    }

    fn alt_shape(&self, a: AltId) -> Shape {
        use Leaf::*;
        let def = &self.m.alts[a.index()];
        let cases: Vec<Vec<Leaf>> = def
            .cases
            .iter()
            .map(|c| c.fields.iter().flat_map(|f| self.leaves(f.1)).collect())
            .collect();
        // Payload slots are shared per leaf kind, widest first so each stays aligned.
        const KINDS: [Leaf; 7] = [I64, F64, F32, N32, N16, N8, I8];
        let count = |l: Leaf| {
            cases
                .iter()
                .map(|c| c.iter().filter(|x| **x == l).count())
                .max()
                .unwrap_or(0)
        };
        let mut block = vec![I64];
        let mut first = [0usize; 7];
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
        if self.is_boxed(a) {
            Shape {
                leaves: vec![I64],
                alt: Some(AltRepr::Boxed { slots, block }),
            }
        } else {
            Shape {
                leaves: block,
                alt: Some(AltRepr::Inline { slots }),
            }
        }
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
