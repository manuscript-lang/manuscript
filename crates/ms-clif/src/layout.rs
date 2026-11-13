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
//! | `Int`, `Ptr`, closures | `i64` |
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
use std::cell::RefCell;
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

    /// The memory bytes of the constant list elements `raw` of this leaf: each element's low
    /// `size()` bytes, except a `Float32`, which is held as `f64` bits and stored as a binary32.
    pub fn const_bytes(self, raw: &[i64]) -> Vec<u8> {
        let width = self.size() as usize;
        raw.iter()
            .flat_map(|&v| match self {
                Leaf::F32 => (f64::from_bits(v as u64) as f32).to_le_bytes().to_vec(),
                _ => v.to_le_bytes()[..width].to_vec(),
            })
            .collect()
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
    /// Shapes indexed by type, filled on first ask.
    shapes: RefCell<Vec<Option<Rc<Shape>>>>,
    /// Alternative fields indexed by alternative.
    alt_fields: RefCell<Vec<Option<Rc<AltFields>>>>,
    boxing: RefCell<Boxing>,
}

/// Per case, per field: the field's type and its leaf indices into the alternative's leaf list.
pub type AltFields = Vec<Vec<(Ty, Vec<usize>)>>;

impl<'m> Layouts<'m> {
    /// A fresh oracle.
    pub fn new(m: &'m Module) -> Self {
        Layouts {
            m,
            shapes: RefCell::new(vec![None; m.types.len()]),
            alt_fields: RefCell::new(vec![None; m.alts.len()]),
            boxing: RefCell::new(Boxing::default()),
        }
    }

    /// Whether the alternative contains itself by value and therefore lives behind a pointer.
    pub fn is_boxed(&self, a: AltId) -> bool {
        self.boxing.borrow_mut().alt(self.m, a)
    }

    /// Whether `inner?` contains itself by value (`type Node: next: Node?`)
    /// and therefore holds its payload in a heap block behind a nullable pointer.
    pub fn opt_is_boxed(&self, inner: Ty) -> bool {
        self.boxing.borrow_mut().opt(self.m, inner)
    }

    /// The flattened shape of `ty`.
    ///
    /// Shared: every instruction asks, and copying the leaves and case slots of a large
    /// alternative each time made lowering quadratic in its case count.
    pub fn shape(&self, ty: Ty) -> Rc<Shape> {
        if let Some(s) = &self.shapes.borrow()[ty.index()] {
            return s.clone();
        }
        if let TyKind::Alt(a) = self.m.types.kind(ty)
            && self.is_boxed(*a)
        {
            // A boxed alternative is one pointer; this also ends the recursion through its own fields.
            self.shapes.borrow_mut()[ty.index()] = Some(Rc::new(Shape {
                leaves: vec![Leaf::I64],
                alt: None,
            }));
        }
        let s = Rc::new(self.compute(ty));
        self.shapes.borrow_mut()[ty.index()] = Some(s.clone());
        s
    }

    /// Per-case, per-field `(type, leaf indices into the alt's leaf/block list)`.
    pub fn alt_fields(&self, a: AltId) -> Rc<AltFields> {
        if let Some(f) = &self.alt_fields.borrow()[a.index()] {
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
        self.alt_fields.borrow_mut()[a.index()] = Some(fields.clone());
        fields
    }

    /// The leaves of the heap block behind an indirect record: its fields' leaves in order, except
    /// that a `Map` or `Set` field is one pointer to a header block that exists only while the
    /// collection is not the all-zero empty value (see [`Layouts::rec_field_boxed`]).
    pub fn rec_block(&self, r: ms_mir::types::RecId) -> Vec<Leaf> {
        self.m.records[r.index()]
            .fields
            .iter()
            .flat_map(|f| {
                if self.rec_field_boxed(f.1) {
                    vec![Leaf::I64]
                } else {
                    self.leaves(f.1)
                }
            })
            .collect()
    }

    /// Whether a field of type `fty` inside an indirect record's block holds a nullable pointer
    /// to its header instead of the header itself. An empty map is seven zero words, so an
    /// `Error` that carries no details has a block of five words and one allocation.
    pub fn rec_field_boxed(&self, fty: Ty) -> bool {
        matches!(self.m.types.kind(fty), TyKind::Obj(n, _) if n.is_map_or_set())
    }

    /// The size in bytes of the heap block of the boxed enum `ty`; `None` for any other type.
    pub fn boxed_block_size(&self, ty: Ty) -> Option<usize> {
        match &self.shape(ty).alt {
            Some(AltRepr::Boxed { block, .. }) => Some(mem_layout(block).size as usize),
            _ => None,
        }
    }

    /// The register leaves of `ty`.
    pub fn leaves(&self, ty: Ty) -> Vec<Leaf> {
        self.shape(ty).leaves.clone()
    }

    /// Which register leaves of `ty` are pointers, one flag per leaf of [`Layouts::leaves`]: a
    /// `ptr`, a function or object handle, an indirect record or boxed alternative or optional
    /// (nullable), a list's data pointer. A string's first word is a tagged encoding and an
    /// inline alternative's payload slots are shared between cases, so those stay integers. A
    /// register leaf is an `i64` for the Cranelift object and the runtime either way; this only
    /// says what the direct LLVM emitter may type as `ptr`.
    pub fn pointer_leaves(&self, ty: Ty) -> Vec<bool> {
        self.marks(ty, true)
    }

    /// Which register leaves of `ty` are booleans, one flag per leaf: a `Bool` and the presence
    /// flag of an optional, both zero or one. The direct LLVM emitter holds them as `i1`.
    pub fn bool_leaves(&self, ty: Ty) -> Vec<bool> {
        self.marks(ty, false)
    }

    /// The leaves that are pointers (`ptr`) or booleans (not `ptr`).
    fn marks(&self, ty: Ty, ptr: bool) -> Vec<bool> {
        let n = self.width(ty);
        let one = |yes: bool| vec![yes];
        match self.m.types.kind(ty) {
            TyKind::Bool => one(!ptr),
            TyKind::Ptr | TyKind::Fn(..) => one(ptr),
            TyKind::Obj(n, _) if !n.is_map_or_set() => one(ptr),
            // The data pointer and the vtable address (tag bits in its low two).
            TyKind::Iface(_) => vec![ptr; 2],
            TyKind::Bytes | TyKind::List(_) => vec![ptr, false, false],
            TyKind::Rec(r) if self.m.records[r.index()].indirect => one(ptr),
            TyKind::Rec(r) => self.m.records[r.index()]
                .fields
                .iter()
                .flat_map(|f| self.marks(f.1, ptr))
                .collect(),
            TyKind::Opt(inner) if self.opt_is_nullable(*inner) => one(ptr),
            TyKind::Opt(inner) if !self.is_str_like(ty) => {
                let mut flags = vec![!ptr];
                flags.extend(self.marks(*inner, ptr));
                flags
            }
            TyKind::Alt(a) if self.is_boxed(*a) => one(ptr),
            _ => vec![false; n],
        }
    }

    /// Number of register leaves.
    pub fn width(&self, ty: Ty) -> usize {
        self.shape(ty).leaves.len()
    }

    /// Memory layout of `ty`.
    pub fn mem(&self, ty: Ty) -> MemLayout {
        mem_layout(&self.shape(ty).leaves)
    }

    /// Whether `inner?` is a nullable pointer.
    pub fn opt_is_nullable(&self, inner: Ty) -> bool {
        self.opt_is_boxed(inner)
            || matches!(self.m.types.kind(inner), TyKind::Fn(..))
            || matches!(self.m.types.kind(inner), TyKind::Obj(n, _) if !n.is_map_or_set())
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
            TyKind::UInt8 => plain(vec![U8]),
            TyKind::UInt16 => plain(vec![U16]),
            TyKind::UInt32 => plain(vec![U32]),
            TyKind::UInt64 => plain(vec![I64]),
            TyKind::Float => plain(vec![F64]),
            TyKind::Float32 => plain(vec![F32]),
            TyKind::Str => plain(vec![I64, I64]),
            TyKind::Bytes | TyKind::List(_) => plain(vec![I64, I64, I64]),
            TyKind::Obj(n, _) if n.is_map_or_set() => plain(vec![I64; ms_rt_abi::MAP_SIZE / 8]),
            TyKind::Obj(..) => plain(vec![I64]),
            TyKind::Iface(_) => plain(vec![I64, I64]),
            TyKind::Rec(r) if self.m.records[r.index()].indirect => plain(vec![I64]),
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

    #[test]
    fn pointer_leaves_match_the_leaves() {
        let mut m = Module::new("t");
        let list = m.types.list(Ty::INT);
        let opt_list = m.types.opt(list);
        let opt_bool = m.types.opt(Ty::BOOL);
        let (_, rec) = m.add_record(
            "R",
            vec![
                ("p".into(), Ty::PTR),
                ("l".into(), list),
                ("n".into(), Ty::INT),
            ],
        );
        let lay = Layouts::new(&m);
        for t in [Ty::PTR, Ty::STR, list, opt_list, rec, Ty::INT] {
            assert_eq!(lay.pointer_leaves(t).len(), lay.width(t), "{t:?}");
        }
        assert_eq!(lay.pointer_leaves(list), vec![true, false, false]);
        assert_eq!(
            lay.pointer_leaves(rec),
            vec![true, true, false, false, false]
        );
        assert_eq!(lay.pointer_leaves(Ty::STR), vec![false, false]);
        for t in [Ty::BOOL, opt_bool, rec] {
            assert_eq!(lay.bool_leaves(t).len(), lay.width(t), "{t:?}");
        }
        assert_eq!(lay.bool_leaves(Ty::BOOL), vec![true]);
        // Presence flag and value of `Bool?`; no booleans in a list or a string.
        assert_eq!(lay.bool_leaves(opt_bool), vec![true, true]);
        assert_eq!(lay.bool_leaves(list), vec![false; 3]);
    }

    #[test]
    fn indirect_record_is_one_pointer() {
        let mut m = Module::new("t");
        let (id, ty) = m.add_record("Big", vec![("a".into(), Ty::STR), ("b".into(), Ty::INT)]);
        assert_eq!(Layouts::new(&m).width(ty), 3);
        m.records[id.index()].indirect = true;
        let lay = Layouts::new(&m);
        assert_eq!(lay.leaves(ty), vec![Leaf::I64]);
        assert_eq!(lay.rec_block(id).len(), 3);
    }
}
