//! Binary contract between generated code and the Manuscript runtime (`ms-rt`).
//!
//! Everything here is `repr(C)`, `no_std` and dependency free. The code generator
//! reads these constants instead of hard-coding offsets; `ms-rt` implements the
//! behavior. The prose contract lives in `crates/ms-rt/ABI.md`; this file is the
//! machine-checked half (see the layout tests at the bottom).
//!
//! Pointers named `*mut Obj` always point at an object *header*.
#![no_std]

/// Bump when any layout or symbol here changes incompatibly.
pub const ABI_VERSION: u32 = 1;

// ---------------------------------------------------------------------------
// Object header and reference counting
// ---------------------------------------------------------------------------

/// Reference count given to static and literal objects. Counts never reach zero
/// in practice (2^62 decrements), so count updates on them are harmless and the
/// generated code needs no immortality check.
pub const STATIC_RC: usize = 1 << 62;

/// Drop entry of an object header. Called when the count reaches zero. The
/// function releases the object's children and then frees its own memory with
/// `msrt_free(obj)`.
pub type DropFn = unsafe extern "C" fn(*mut Obj);

/// The 16-byte header every heap object starts with.
#[repr(C)]
pub struct Obj {
    /// Non-atomic reference count (the language has no concurrency).
    pub rc: usize,
    /// Drop protocol entry; never null for a live object.
    pub drop: Option<DropFn>,
}

pub const OBJ_RC_OFFSET: usize = 0;
pub const OBJ_DROP_OFFSET: usize = 8;
pub const OBJ_HEADER_SIZE: usize = 16;

// ---------------------------------------------------------------------------
// String and Bytes
// ---------------------------------------------------------------------------

/// `scalars` value meaning "not counted yet".
pub const SCALARS_UNKNOWN: usize = usize::MAX;

/// `String`: header, UTF-8 byte length, cached Unicode scalar count, bytes, and
/// one trailing NUL byte (not counted in `len`). Strings are immutable.
/// `Bytes` uses the same layout with `scalars` unused (always 0).
#[repr(C)]
pub struct StrObj {
    pub hdr: Obj,
    /// Byte length.
    pub len: usize,
    /// Scalar count or [`SCALARS_UNKNOWN`]. Written lazily by `length()`.
    pub scalars: usize,
    // `len + 1` bytes of data follow at offset 32.
}

pub const STR_LEN_OFFSET: usize = 16;
pub const STR_SCALARS_OFFSET: usize = 24;
pub const STR_DATA_OFFSET: usize = 32;
/// Bytes shares the String layout.
pub const BYTES_LEN_OFFSET: usize = STR_LEN_OFFSET;
pub const BYTES_DATA_OFFSET: usize = STR_DATA_OFFSET;

// ---------------------------------------------------------------------------
// Type descriptors
// ---------------------------------------------------------------------------

/// How a slot of a given type is dropped, copied, compared and hashed.
pub const KIND_INT: u32 = 0;
pub const KIND_FLOAT: u32 = 1;
pub const KIND_BOOL: u32 = 2;
/// Slot holds a non-null `*mut StrObj`; content equality and hashing.
pub const KIND_STRING: u32 = 3;
/// Slot holds a non-null `*mut StrObj` used as Bytes; content equality and hashing.
pub const KIND_BYTES: u32 = 4;
/// Slot holds one nullable object pointer. Drop and copy are the builtin
/// release/retain; `eq` and `hash` are called when present, else identity.
pub const KIND_PTR: u32 = 5;
/// Slot is plain bits without references (for example an inline `Optional[Int]`).
/// Equality is `memcmp` and hashing is over the bytes unless `eq`/`hash` is set.
pub const KIND_POD: u32 = 6;
/// Everything goes through the function pointers of the descriptor.
pub const KIND_CUSTOM: u32 = 7;

/// Drops the value stored in a slot (releases the references it owns).
pub type SlotDropFn = unsafe extern "C" fn(slot: *mut u8);
/// Adds one reference for every reference the slot's value holds. Used after a
/// bitwise copy of a slot.
pub type SlotRetainFn = unsafe extern "C" fn(slot: *const u8);
/// Equality of two slots; returns 0 or 1.
pub type SlotEqFn = unsafe extern "C" fn(a: *const u8, b: *const u8) -> u8;
/// Hash of a slot. Equal values must hash equally.
pub type SlotHashFn = unsafe extern "C" fn(slot: *const u8) -> i64;

/// Element or key/value descriptor. The compiler emits one static, read-only
/// descriptor per distinct slot type; the runtime provides builtins for `Int`,
/// `Float`, `Bool`, `String` and `Bytes` (`msrt_desc_*`).
#[repr(C)]
pub struct TypeDesc {
    /// Slot size in bytes, a multiple of `align`. Zero is allowed (Unit).
    pub size: u32,
    /// Slot alignment, 1, 2, 4, 8 or 16.
    pub align: u32,
    /// One of the `KIND_*` constants.
    pub kind: u32,
    pub reserved: u32,
    /// `KIND_CUSTOM`: drop of the slot (`None` when it owns nothing).
    pub drop: Option<SlotDropFn>,
    /// `KIND_CUSTOM`: retain after bitwise copy (`None` when it holds no references).
    pub retain: Option<SlotRetainFn>,
    /// `KIND_PTR`/`KIND_CUSTOM`/`KIND_POD`: equality override.
    pub eq: Option<SlotEqFn>,
    /// `KIND_PTR`/`KIND_CUSTOM`/`KIND_POD`: hash override.
    pub hash: Option<SlotHashFn>,
}

pub const DESC_SIZE_OFFSET: usize = 0;
pub const DESC_ALIGN_OFFSET: usize = 4;
pub const DESC_KIND_OFFSET: usize = 8;
pub const DESC_DROP_OFFSET: usize = 16;
pub const DESC_RETAIN_OFFSET: usize = 24;
pub const DESC_EQ_OFFSET: usize = 32;
pub const DESC_HASH_OFFSET: usize = 40;

// SAFETY-free marker: descriptors contain only function pointers and integers.
// They are immutable statics, so sharing them between threads is sound.
unsafe impl Sync for TypeDesc {}

// ---------------------------------------------------------------------------
// List, Map, Set and builders
// ---------------------------------------------------------------------------

/// Set on a builder object after `freeze`; mutation faults with "builder is sealed".
pub const FLAG_SEALED: usize = 1;

/// `List[T]`, `ListBuilder[T]` (same object; `freeze` returns it and seals the
/// builder flag). Elements are stored inline, `desc.size` bytes apart, starting
/// at `data`. `data` is null while `cap == 0`.
#[repr(C)]
pub struct ListObj {
    pub hdr: Obj,
    pub len: usize,
    pub cap: usize,
    pub data: *mut u8,
    pub desc: *const TypeDesc,
    pub flags: usize,
}

pub const LIST_LEN_OFFSET: usize = 16;
pub const LIST_CAP_OFFSET: usize = 24;
pub const LIST_DATA_OFFSET: usize = 32;
pub const LIST_DESC_OFFSET: usize = 40;
pub const LIST_FLAGS_OFFSET: usize = 48;
pub const LIST_SIZE: usize = 56;

/// `Map[K, V]` and `Set[T]` (a set has no value descriptor), plus their
/// builders. Insertion ordered: `slots` is an append-only array of entries and
/// `index` an open-addressing hash index of slot numbers. The fields after
/// `flags` are internal to the runtime; generated code may only rely on `len`.
#[repr(C)]
pub struct MapObj {
    pub hdr: Obj,
    /// Number of live entries.
    pub len: usize,
    pub slots: *mut u8,
    /// Slots used so far, including removed ones.
    pub used: usize,
    /// Slot capacity.
    pub cap: usize,
    pub index: *mut u32,
    pub mask: usize,
    pub kdesc: *const TypeDesc,
    /// Null for sets.
    pub vdesc: *const TypeDesc,
    pub flags: usize,
    pub key_off: u32,
    pub val_off: u32,
    pub stride: u32,
    pub reserved: u32,
}

pub const MAP_LEN_OFFSET: usize = 16;

/// `StringBuilder`: appends into a String-shaped buffer with spare capacity;
/// `freeze` returns that buffer (+1) and seals the builder.
#[repr(C)]
pub struct StrBuilderObj {
    pub hdr: Obj,
    /// `*mut StrObj` with capacity `cap` data bytes (not counting the NUL).
    pub buf: *mut StrObj,
    pub cap: usize,
    pub flags: usize,
}

// ---------------------------------------------------------------------------
// Optional, Result, closures, interfaces
// ---------------------------------------------------------------------------

/// `Optional[Int]` and other 8-byte scalars: `{ present, value }`, 16 bytes.
#[repr(C)]
pub struct OptInt {
    pub present: u8,
    pub value: i64,
}
/// `Optional[Float]`.
#[repr(C)]
pub struct OptFloat {
    pub present: u8,
    pub value: f64,
}
/// `Optional[Bool]`.
#[repr(C)]
pub struct OptBool {
    pub present: u8,
    pub value: u8,
}
pub const OPT_SCALAR_VALUE_OFFSET_8: usize = 8;
pub const OPT_BOOL_VALUE_OFFSET: usize = 1;
pub const OPT_INT_SIZE: usize = 16;

/// Function value: header, code pointer, then captured values chosen by the
/// compiler. Calling convention of `code` is `extern "C" fn(closure: *mut Closure, args...)`.
#[repr(C)]
pub struct Closure {
    pub hdr: Obj,
    pub code: *const u8,
}
pub const CLOSURE_CODE_OFFSET: usize = 16;
pub const CLOSURE_CAPTURE_OFFSET: usize = 24;

/// Interface (contract view) value passed or stored inline: `{ data, vtable }`.
#[repr(C)]
pub struct FatPtr {
    pub data: *mut Obj,
    pub vtable: *const u8,
}
pub const FATPTR_SIZE: usize = 16;

// ---------------------------------------------------------------------------
// Status codes of fallible natives
// ---------------------------------------------------------------------------

/// Success. Fallible natives return a `u8` status and write the ok value
/// through a trailing out-pointer. Non-zero values are error cases.
pub const STATUS_OK: u8 = 0;
/// `StringError`/`NumberError`/`CollectionError` case `InvalidInput`.
pub const STATUS_INVALID_INPUT: u8 = 1;
/// `StringError.OutOfRange`, `NumberError.OutOfRange`, `CollectionError.OutOfRange`.
pub const STATUS_OUT_OF_RANGE: u8 = 2;
/// `StringError.LimitExceeded`, `CollectionError.LimitExceeded`.
pub const STATUS_LIMIT_EXCEEDED: u8 = 3;
/// `NumberError.InvalidData`.
pub const STATUS_INVALID_DATA: u8 = 4;

// ---------------------------------------------------------------------------
// Faults, call depth, tables
// ---------------------------------------------------------------------------

/// Maximum nested calls of functions in a recursive cycle.
pub const MAX_CALL_DEPTH: i64 = 200_000;
/// Fault frames shown before "... outer frames omitted".
pub const MAX_FAULT_FRAMES: usize = 32;
/// Exit statuses.
pub const EXIT_FAULT: i32 = 70;
pub const EXIT_INTERRUPT: i32 = 130;
pub const EXIT_TERMINATE: i32 = 143;
/// Largest `main` return value.
pub const MAX_MAIN_EXIT: i64 = 125;

/// One function of the symbol table (`FuncTable`). Entries are sorted by
/// `addr` and must not overlap. Used by fault traces, the profiler and the
/// perf map writer.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct FuncEntry {
    pub addr: usize,
    pub size: u32,
    /// Offset of the NUL-terminated source name (for example `inner`,
    /// `Point.norm`, `main.lambda1`) in the string blob.
    pub name_off: u32,
    /// Offset of the NUL-terminated file path as shown in fault traces.
    pub file_off: u32,
    /// 1-based line of the function declaration.
    pub line: u32,
}
pub const FUNC_ENTRY_SIZE: usize = 24;

/// One call-site line entry (`LineTable`), sorted by `pc`. `pc` is the address of
/// the instruction after the call (the return address). A fault frame's line is
/// the entry with the greatest `pc` that is `<=` the frame's return address.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct LineEntry {
    pub pc: usize,
    pub line: u32,
    /// Offset of the NUL-terminated file path, or `u32::MAX` to use the function's file.
    pub file_off: u32,
}
pub const LINE_ENTRY_SIZE: usize = 16;

/// Tables the compiler emits and passes to `msrt_start`. All pointers may be
/// null with a zero count when no table is available.
#[repr(C)]
pub struct Tables {
    pub abi_version: u32,
    pub reserved: u32,
    pub funcs: *const FuncEntry,
    pub func_count: usize,
    pub lines: *const LineEntry,
    pub line_count: usize,
    /// String blob that `*_off` fields index into.
    pub strings: *const u8,
    pub strings_len: usize,
}

// SAFETY-free marker: the table is plain read-only data emitted by the compiler.
unsafe impl Sync for Tables {}

/// Names of the data symbols generated code reads or writes directly.
pub mod symbols {
    /// `i64`: current depth of recursive calls. Inline protocol: increment, compare
    /// against [`MAX_CALL_DEPTH`](super::MAX_CALL_DEPTH), call `msrt_fault_depth` when greater;
    /// decrement on every return path.
    pub const CALL_DEPTH: &str = "msrt_call_depth";
    /// `u8`: non-zero when a stop request (SIGINT, SIGTERM) is pending and not shielded.
    pub const CANCEL_FLAG: &str = "msrt_cancel_flag";
    pub const DESC_INT: &str = "msrt_desc_int";
    pub const DESC_FLOAT: &str = "msrt_desc_float";
    pub const DESC_BOOL: &str = "msrt_desc_bool";
    pub const DESC_STRING: &str = "msrt_desc_string";
    pub const DESC_BYTES: &str = "msrt_desc_bytes";
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{offset_of, size_of};

    #[test]
    fn layouts_match_constants() {
        assert_eq!(size_of::<Obj>(), OBJ_HEADER_SIZE);
        assert_eq!(offset_of!(Obj, rc), OBJ_RC_OFFSET);
        assert_eq!(offset_of!(Obj, drop), OBJ_DROP_OFFSET);
        assert_eq!(offset_of!(StrObj, len), STR_LEN_OFFSET);
        assert_eq!(offset_of!(StrObj, scalars), STR_SCALARS_OFFSET);
        assert_eq!(size_of::<StrObj>(), STR_DATA_OFFSET);
        assert_eq!(offset_of!(ListObj, len), LIST_LEN_OFFSET);
        assert_eq!(offset_of!(ListObj, cap), LIST_CAP_OFFSET);
        assert_eq!(offset_of!(ListObj, data), LIST_DATA_OFFSET);
        assert_eq!(offset_of!(ListObj, desc), LIST_DESC_OFFSET);
        assert_eq!(offset_of!(ListObj, flags), LIST_FLAGS_OFFSET);
        assert_eq!(size_of::<ListObj>(), LIST_SIZE);
        assert_eq!(offset_of!(MapObj, len), MAP_LEN_OFFSET);
        assert_eq!(offset_of!(Closure, code), CLOSURE_CODE_OFFSET);
        assert_eq!(size_of::<Closure>(), CLOSURE_CAPTURE_OFFSET);
        assert_eq!(size_of::<OptInt>(), OPT_INT_SIZE);
        assert_eq!(offset_of!(OptInt, value), OPT_SCALAR_VALUE_OFFSET_8);
        assert_eq!(offset_of!(OptFloat, value), OPT_SCALAR_VALUE_OFFSET_8);
        assert_eq!(offset_of!(OptBool, value), OPT_BOOL_VALUE_OFFSET);
        assert_eq!(size_of::<FatPtr>(), FATPTR_SIZE);
        assert_eq!(offset_of!(TypeDesc, drop), DESC_DROP_OFFSET);
        assert_eq!(offset_of!(TypeDesc, retain), DESC_RETAIN_OFFSET);
        assert_eq!(offset_of!(TypeDesc, eq), DESC_EQ_OFFSET);
        assert_eq!(offset_of!(TypeDesc, hash), DESC_HASH_OFFSET);
        assert_eq!(size_of::<FuncEntry>(), FUNC_ENTRY_SIZE);
        assert_eq!(size_of::<LineEntry>(), LINE_ENTRY_SIZE);
        assert_eq!(size_of::<usize>(), 8, "64-bit targets only");
    }
}
