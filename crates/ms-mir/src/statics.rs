//! Static data that every backend emits the same way: type descriptors, shared blocks of
//! payloadless alternative cases, and string literal words. MIR decides what the data holds; a
//! backend only writes the bytes and relocations in its own object format.

use crate::ir::{FuncId, Module};
use crate::layout::Layouts;
use crate::types::{Native, Ty, TyKind};
use ms_rt_abi::{
    KIND_CUSTOM, KIND_LIST, KIND_MAP, KIND_POD, KIND_SET, KIND_SHARED, STR_INLINE,
    STR_INLINE_LEN_SHIFT, STR_INLINE_MAX, STR_STATIC,
};

/// How a backend materializes the descriptor of one type key.
pub enum DescPlan {
    /// A descriptor the runtime defines, by symbol.
    Runtime(&'static str),
    /// A static table (`crates/ms-rt/ABI.md`, section 5) the backend emits.
    Table(DescTable),
}

/// The contents of a descriptor table, with each address named by what it points at.
pub struct DescTable {
    pub size: u32,
    pub align: u32,
    pub kind: u32,
    /// Descriptor keys of the element (list, set) or key and value (map) types, already carrying
    /// the implementation scope of the table.
    pub inner: [Option<Ty>; 2],
    /// The unscoped type whose slot drop and slot copy glue the table points at, for a custom kind.
    pub slot_glue: Option<Ty>,
    /// The `Equal` and `Hashable` glue of the type, when it has any.
    pub eq_hash: Option<(FuncId, FuncId)>,
}

/// The descriptor of key `key` (a type under an implementation scope; `0` is none).
pub fn descriptor(m: &Module, lay: &Layouts, key: Ty) -> DescPlan {
    // A scoped key names the same layout with the glue of one module's local implementations.
    let scope = key.scope();
    let ty = key.unscoped();
    let runtime = match m.types.kind(ty) {
        // `Int8`..`Int32` and `UInt8`..`UInt64` are plain bits of their width and take the plain
        // path below.
        TyKind::Int => Some("msrt_desc_int"),
        TyKind::Float => Some("msrt_desc_float"),
        TyKind::Float32 => Some("msrt_desc_float32"),
        TyKind::Bool => Some("msrt_desc_bool"),
        TyKind::Str => Some("msrt_desc_string"),
        TyKind::Bytes => Some("msrt_desc_bytes"),
        _ => None,
    };
    if let Some(name) = runtime {
        return DescPlan::Runtime(name);
    }
    let mem = lay.mem(ty);
    let mut inner: [Option<Ty>; 2] = [None, None];
    let mut slot_glue = None;
    let kind = match m.types.kind(ty) {
        TyKind::List(e) => {
            inner[0] = Some(*e);
            KIND_LIST
        }
        TyKind::Obj(Native::Map, args) => {
            inner = [args.first().copied(), args.get(1).copied()];
            KIND_MAP
        }
        TyKind::Obj(Native::Set, args) => {
            inner[0] = args.first().copied();
            KIND_SET
        }
        TyKind::Obj(..) | TyKind::Fn(..) => KIND_SHARED,
        TyKind::Opt(i) if lay.opt_is_nullable(*i) => KIND_SHARED,
        _ if !m.needs_drop(ty) => KIND_POD,
        _ => {
            slot_glue = Some(ty);
            KIND_CUSTOM
        }
    };
    // The scope's own glue, else the unscoped one.
    let eq_hash = m
        .desc_glue
        .iter()
        .find(|(t, _, _)| *t == key)
        .or_else(|| m.desc_glue.iter().find(|(t, _, _)| *t == ty))
        .map(|&(_, eq, hash)| (eq, hash));
    DescPlan::Table(DescTable {
        size: mem.size,
        align: mem.align,
        kind,
        inner: inner.map(|t| t.map(|t| t.scoped(scope))),
        slot_glue,
        eq_hash,
    })
}

/// The bytes of the shared block of payloadless case `case` of a boxed alternative: `size` zero
/// bytes with the tag stored first. Such values never allocate, and dropping them frees nothing.
pub fn unit_block(case: usize, size: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; size.max(8)];
    bytes[0..8].copy_from_slice(&(case as u64).to_le_bytes());
    bytes
}

/// The two words of a string literal value.
pub enum StrLit {
    /// A short literal held in its words: no data symbol.
    Inline { lo: u64, hi: u64 },
    /// A literal in static data: the address word is the data, the tag word is this.
    Static { tagged: u64 },
}

/// The words of literal `s`. A short literal is an inline string, so comparisons with other short
/// strings decide from the second word; any other is a static string over NUL-terminated data.
pub fn str_lit(s: &str) -> StrLit {
    let bytes = s.as_bytes();
    if bytes.len() > STR_INLINE_MAX {
        return StrLit::Static {
            tagged: (bytes.len() | STR_STATIC) as u64,
        };
    }
    let bits = bytes
        .iter()
        .enumerate()
        .fold(0u128, |acc, (i, b)| acc | (*b as u128) << (8 * i));
    StrLit::Inline {
        lo: bits as u64,
        hi: ((bits >> 64) as u64 as usize | STR_INLINE | (bytes.len() << STR_INLINE_LEN_SHIFT))
            as u64,
    }
}

/// The static data of literal `s`: its bytes then a NUL.
pub fn str_data(s: &str) -> Vec<u8> {
    let mut bytes = s.as_bytes().to_vec();
    bytes.push(0);
    bytes
}
