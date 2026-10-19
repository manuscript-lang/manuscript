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
//! | `Int`, `Ptr`, `String`, closures, `Shared[T]` | `i64` |
//! | `Float` | `f64` |
//! | `List[T]`, `Bytes` | `ptr, len, cap` |
//! | `Map`, `Set` | six `i64` words (`MapVal`) |
//! | record | the fields' leaves in declaration order |
//! | `Optional[String]` (single-pointer payloads) | nullable `i64` |
//! | `Optional[T]` otherwise | `present: i8`, then `T`'s leaves |
//! | alternative | `tag: i64`, then payload slots shared by all cases |
//! | recursive alternative | `i64` pointer to a heap block `{ tag, payload }` |
//! | interface | `data, vtable` |

use ms_mir::ir::Module;
use ms_mir::types::{AltId, Ty, TyKind};
use std::cell::RefCell;
use std::collections::HashMap;

/// A scalar machine value.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Leaf {
    /// 64-bit integer or pointer.
    I64,
    /// 64-bit float.
    F64,
    /// Byte (booleans, presence flags).
    I8,
}

impl Leaf {
    /// Size and alignment in bytes.
    pub fn size(self) -> u32 {
        match self {
            Leaf::I8 => 1,
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
    /// Alignment (1 for empty or all-byte, else 8).
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
    cache: RefCell<HashMap<Ty, Shape>>,
    boxed: RefCell<HashMap<AltId, bool>>,
}

impl<'m> Layouts<'m> {
    /// A fresh oracle.
    pub fn new(m: &'m Module) -> Self {
        Layouts {
            m,
            cache: RefCell::new(HashMap::new()),
            boxed: RefCell::new(HashMap::new()),
        }
    }

    /// Whether the alternative contains itself by value and therefore lives behind a pointer.
    pub fn is_boxed(&self, a: AltId) -> bool {
        if let Some(b) = self.boxed.borrow().get(&a) {
            return *b;
        }
        // Provisional answer for cycles through other alternatives.
        self.boxed.borrow_mut().insert(a, false);
        let target = self.m.types.find(&TyKind::Alt(a));
        let b = target.is_some_and(|t| self.reaches_by_value(t, t, &mut Vec::new()));
        self.boxed.borrow_mut().insert(a, b);
        b
    }

    fn reaches_by_value(&self, from: Ty, target: Ty, seen: &mut Vec<Ty>) -> bool {
        let children: Vec<Ty> = match self.m.types.kind(from) {
            TyKind::Rec(r) => self.m.records[r.index()]
                .fields
                .iter()
                .map(|f| f.1)
                .collect(),
            TyKind::Alt(a) => self.m.alts[a.index()]
                .cases
                .iter()
                .flat_map(|c| c.fields.iter().map(|f| f.1))
                .collect(),
            TyKind::Opt(t) => vec![*t],
            _ => return false,
        };
        for c in children {
            if c == target {
                return true;
            }
            if seen.contains(&c) {
                continue;
            }
            seen.push(c);
            // Stop at other boxed alternatives: they are one pointer.
            if let TyKind::Alt(a) = self.m.types.kind(c)
                && self.is_boxed(*a)
            {
                continue;
            }
            if self.reaches_by_value(c, target, seen) {
                return true;
            }
        }
        false
    }

    /// The flattened shape of `ty`.
    pub fn shape(&self, ty: Ty) -> Shape {
        if let Some(s) = self.cache.borrow().get(&ty) {
            return s.clone();
        }
        if let TyKind::Alt(a) = self.m.types.kind(ty)
            && self.is_boxed(*a)
        {
            // A boxed alternative is one pointer; this also ends the recursion through its own fields.
            self.cache.borrow_mut().insert(
                ty,
                Shape {
                    leaves: vec![Leaf::I64],
                    alt: None,
                },
            );
        }
        let s = self.compute(ty);
        self.cache.borrow_mut().insert(ty, s.clone());
        s
    }

    /// The register leaves of `ty`.
    pub fn leaves(&self, ty: Ty) -> Vec<Leaf> {
        self.shape(ty).leaves
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
        matches!(self.m.types.kind(inner), TyKind::Str | TyKind::Fn(..))
            || matches!(self.m.types.kind(inner), TyKind::Obj(n, _) if n != "Map" && n != "Set")
    }

    fn compute(&self, ty: Ty) -> Shape {
        use Leaf::*;
        let plain = |leaves: Vec<Leaf>| Shape { leaves, alt: None };
        match self.m.types.kind(ty) {
            TyKind::Unit => plain(vec![]),
            TyKind::Bool => plain(vec![I8]),
            TyKind::Int | TyKind::Ptr | TyKind::Str | TyKind::Fn(..) => plain(vec![I64]),
            TyKind::Float => plain(vec![F64]),
            TyKind::Bytes | TyKind::List(_) => plain(vec![I64, I64, I64]),
            TyKind::Obj(n, _) if n == "Map" || n == "Set" => plain(vec![I64; 6]),
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
        let count = |l: Leaf| {
            cases
                .iter()
                .map(|c| c.iter().filter(|x| **x == l).count())
                .max()
                .unwrap_or(0)
        };
        let (n64, nf, n8) = (count(I64), count(F64), count(I8));
        let mut block = vec![I64];
        block.extend(std::iter::repeat_n(I64, n64));
        block.extend(std::iter::repeat_n(F64, nf));
        block.extend(std::iter::repeat_n(I8, n8));
        let slots: Vec<Vec<usize>> = cases
            .iter()
            .map(|c| {
                let (mut a64, mut af, mut a8) = (1, 1 + n64, 1 + n64 + nf);
                c.iter()
                    .map(|l| {
                        let next = match l {
                            I64 => &mut a64,
                            F64 => &mut af,
                            I8 => &mut a8,
                        };
                        let i = *next;
                        *next += 1;
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
