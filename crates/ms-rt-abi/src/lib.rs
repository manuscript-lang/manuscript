//! Binary contract between generated code and the Manuscript runtime (`ms-rt`).
//!
//! Everything here is `repr(C)`, `no_std` and dependency free. The code generator
//! reads these constants instead of hard-coding offsets; `ms-rt` implements the
//! behavior. The prose contract lives in `crates/ms-rt/ABI.md`; this file is the
//! machine-checked half (see the layout tests at the bottom).
//!
//! Pointers named `*mut Obj` always point at an object *header*.
#![no_std]
// `unsafe extern "C" fn` pointer types and `Sync` impls for the C-layout statics.
#![allow(unsafe_code)]

/// Bump when any layout or symbol here changes incompatibly.
pub const ABI_VERSION: u32 = 2;

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
// String
// ---------------------------------------------------------------------------

/// `String`: two words in the owner's slot, `ptr` at the UTF-8 bytes and `len` the byte length
/// with the ownership tag in its top two bits. The bytes are followed by one NUL (not counted).
///
/// A string is an owned value over immutable bytes: copying it allocates and copies the bytes,
/// dropping it frees them. The tag says what the bytes are:
///
/// | top bits | kind | drop | copy |
/// | --- | --- | --- | --- |
/// | `00` | owned allocation starting at `ptr` | frees | duplicates |
/// | `10` | static (a literal or a shared one-byte ASCII string) | nothing | shares |
/// | `11` | view borrowed from another string | nothing | duplicates |
///
/// So `tagged as i64 >= 0` is "owned", and the length is `tagged & STR_LEN_MASK`.
#[repr(C)]
pub struct StrVal {
    pub ptr: *mut u8,
    /// Byte length and tag; read it through [`StrVal::len`].
    pub tagged: usize,
}
/// Tag bit of a string that is not owned (static or view).
pub const STR_BORROWED: usize = 1 << 63;
/// Tag of a static string.
pub const STR_STATIC: usize = STR_BORROWED;
/// Tag of a view.
pub const STR_VIEW: usize = 3 << 62;
/// Mask of the byte length in the second word.
pub const STR_LEN_MASK: usize = (1 << 62) - 1;

impl StrVal {
    /// An owned string over the allocation at `ptr`.
    #[inline(always)]
    pub const fn owned(ptr: *mut u8, len: usize) -> StrVal {
        StrVal { ptr, tagged: len }
    }

    /// A static string (never freed, shared on copy).
    #[inline(always)]
    pub const fn literal(ptr: *mut u8, len: usize) -> StrVal {
        StrVal {
            ptr,
            tagged: len | STR_STATIC,
        }
    }

    /// A view of bytes another string owns.
    #[inline(always)]
    pub const fn view(ptr: *mut u8, len: usize) -> StrVal {
        StrVal {
            ptr,
            tagged: len | STR_VIEW,
        }
    }

    /// Byte length.
    #[inline(always)]
    pub const fn len(&self) -> usize {
        self.tagged & STR_LEN_MASK
    }

    /// Whether the string has no bytes.
    #[inline(always)]
    pub const fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Whether dropping the string frees an allocation (not a literal and not a view).
    #[inline(always)]
    pub const fn owns(&self) -> bool {
        (self.tagged as isize) >= 0
    }

    /// Whether the string is static: copies share it.
    #[inline(always)]
    pub const fn is_static(&self) -> bool {
        self.tagged >> 62 == 2
    }

    /// Whether the string is a view of another string's bytes.
    #[inline(always)]
    pub const fn is_view(&self) -> bool {
        self.tagged >> 62 == 3
    }

    /// A second handle to the same bytes. Every call site decides what it stands for (a move or
    /// a short-lived borrow); the compiler no longer duplicates strings silently, so
    /// `grep alias` lists every site that shares.
    #[inline(always)]
    pub fn alias(&self) -> StrVal {
        StrVal {
            ptr: self.ptr,
            tagged: self.tagged,
        }
    }

    /// Writes the two words to `out` as separate stores. A plain struct write lets the compiler
    /// copy through a 16-byte vector move, which stalls reading words a callee just stored
    /// separately.
    ///
    /// # Safety
    /// `out` must be writable.
    #[inline(always)]
    pub unsafe fn write_to(self, out: *mut StrVal) {
        // SAFETY: caller contract.
        unsafe {
            core::ptr::write_volatile(&raw mut (*out).ptr, self.ptr);
            core::ptr::write_volatile(&raw mut (*out).tagged, self.tagged);
        }
    }
}
pub const STR_PTR_OFFSET: usize = 0;
pub const STR_LEN_OFFSET: usize = 8;
pub const STR_SIZE: usize = 16;

/// Distance between consecutive entries of the shared one-character ASCII strings (`msrt_ascii_chars`).
pub const ASCII_CHAR_STRIDE: usize = 2;

/// `Optional[String]`: the string itself (16 bytes); none is a static empty string with a null
/// `ptr`, which no present string has, so dropping or copying none does nothing.
#[repr(C)]
pub struct OptStr {
    pub value: StrVal,
}
pub const OPT_STR_VALUE_OFFSET: usize = 0;
pub const OPT_STR_SIZE: usize = 16;

impl OptStr {
    /// An absent string.
    pub const NONE: OptStr = OptStr {
        value: StrVal {
            ptr: core::ptr::null_mut(),
            tagged: STR_STATIC,
        },
    };

    /// Whether a string is present.
    pub fn is_some(&self) -> bool {
        !self.value.ptr.is_null()
    }
}

// ---------------------------------------------------------------------------
// Owned aggregate values: List, Bytes, Map, Set (no header, no count)
// ---------------------------------------------------------------------------

/// `List[T]`, `Bytes` (T = u8), `StringBuilder` (bytes): three words stored in
/// the owner's slot. `ptr` is null while `cap == 0`. Elements are inline,
/// `desc.size` bytes apart. The value has exactly one owner; the owner's drop
/// drops the elements and frees `ptr`.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct VecVal {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,
}
pub const VEC_PTR_OFFSET: usize = 0;
pub const VEC_LEN_OFFSET: usize = 8;
pub const VEC_CAP_OFFSET: usize = 16;
pub const VEC_SIZE: usize = 24;

/// `Map[K, V]` and `Set[T]`: six words. Insertion ordered: `slots` is an
/// append-only array of entries (`hash: u64` with the top bit set for live
/// entries and 0 for removed ones, then key, then value, `stride` bytes apart)
/// and `index` an open-addressing hash index of `u64` entries (hash tag, slot number). Only `len` is a
/// stable generated-code field; the rest is internal to the runtime.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct MapVal {
    pub slots: *mut u8,
    pub index: *mut u32,
    /// Number of live entries.
    pub len: usize,
    /// Slots used so far, including removed ones.
    pub used: usize,
    /// Slot capacity.
    pub cap: usize,
    /// Index size minus one (0 when there is no index).
    pub mask: usize,
    /// The key descriptor the map was created with, or null to use the caller's.
    pub desc: *const TypeDesc,
}
pub const MAP_LEN_OFFSET: usize = 16;
pub const MAP_SIZE: usize = 56;

// ---------------------------------------------------------------------------
// Type descriptors
// ---------------------------------------------------------------------------

pub const KIND_INT: u32 = 0;
pub const KIND_FLOAT: u32 = 1;
pub const KIND_BOOL: u32 = 2;
/// Slot holds a `StrVal` (16 bytes); copy duplicates, drop frees; content equality and hash.
pub const KIND_STRING: u32 = 3;
/// Slot holds a `VecVal` of bytes (24 bytes). Copy duplicates the buffer.
pub const KIND_BYTES: u32 = 4;
/// Slot holds a nullable pointer to a reference-counted object with an `Obj`
/// header (`Shared[T]`, closures, handle objects...). Copy = retain, drop = release.
/// `eq`/`hash` are called when present, else identity.
pub const KIND_SHARED: u32 = 5;
/// Plain bits without ownership (scalars, records of scalars, inline `Optional[Int]`).
/// Copy is `memcpy`; equality `memcmp` and hash over the bytes unless `eq`/`hash` is set.
pub const KIND_POD: u32 = 6;
/// Slot holds a `VecVal` list whose element descriptor is `inner0`.
pub const KIND_LIST: u32 = 7;
/// Slot holds a `MapVal` map: key `inner0`, value `inner1`.
pub const KIND_MAP: u32 = 8;
/// Slot holds a `MapVal` set: element `inner0`.
pub const KIND_SET: u32 = 9;
/// Records, alternatives and anything else: all behavior through the function pointers.
pub const KIND_CUSTOM: u32 = 10;

/// Drops the value stored in a slot (frees what it owns; the slot memory itself is the caller's).
pub type SlotDropFn = unsafe extern "C" fn(slot: *mut u8);
/// Duplicates the value in `src` into uninitialised `dst` (`.copy()`): owned
/// parts are deep copied, reference-counted parts retained.
pub type SlotCopyFn = unsafe extern "C" fn(src: *const u8, dst: *mut u8);
/// Equality of two slots; returns 0 or 1.
pub type SlotEqFn = unsafe extern "C" fn(a: *const u8, b: *const u8) -> u8;
/// Hash of a slot. Equal values must hash equally.
pub type SlotHashFn = unsafe extern "C" fn(slot: *const u8) -> i64;

/// Slot descriptor. The compiler emits one static, read-only descriptor per
/// distinct slot type; the runtime provides builtins for `Int`, `Float`, `Bool`,
/// `String` and `Bytes` (`msrt_desc_*`).
#[repr(C)]
pub struct TypeDesc {
    /// Slot size in bytes, a multiple of `align`. Zero is allowed (Unit).
    pub size: u32,
    /// Slot alignment, 1, 2, 4, 8 or 16.
    pub align: u32,
    /// One of the `KIND_*` constants.
    pub kind: u32,
    pub reserved: u32,
    /// Element/key descriptor for `LIST`, `MAP`, `SET`.
    pub inner0: *const TypeDesc,
    /// Value descriptor for `MAP`.
    pub inner1: *const TypeDesc,
    /// `CUSTOM`: drop (`None` when it owns nothing).
    pub drop: Option<SlotDropFn>,
    /// `CUSTOM`: deep copy (`None` means bitwise).
    pub copy: Option<SlotCopyFn>,
    /// `SHARED`/`POD`/`CUSTOM`: equality override.
    pub eq: Option<SlotEqFn>,
    /// `SHARED`/`POD`/`CUSTOM`: hash override.
    pub hash: Option<SlotHashFn>,
}

pub const DESC_SIZE_OFFSET: usize = 0;
pub const DESC_ALIGN_OFFSET: usize = 4;
pub const DESC_KIND_OFFSET: usize = 8;
pub const DESC_INNER0_OFFSET: usize = 16;
pub const DESC_INNER1_OFFSET: usize = 24;
pub const DESC_DROP_OFFSET: usize = 32;
pub const DESC_COPY_OFFSET: usize = 40;
pub const DESC_EQ_OFFSET: usize = 48;
pub const DESC_HASH_OFFSET: usize = 56;
pub const DESC_SIZE: usize = 64;

// SAFETY: descriptors contain only pointers to other immutable
// statics, function pointers and integers, so sharing them is sound.
unsafe impl Sync for TypeDesc {}

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

/// Function value (heap object, reference counted): header, code pointer, then captured values chosen by the
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
/// `FileSystemError.NotFound`.
pub const STATUS_NOT_FOUND: u8 = 5;
/// `FileSystemError.AlreadyExists`.
pub const STATUS_ALREADY_EXISTS: u8 = 6;
/// `FileSystemError.NotEmpty`.
pub const STATUS_NOT_EMPTY: u8 = 7;
/// `FileSystemError.PermissionDenied`.
pub const STATUS_PERMISSION_DENIED: u8 = 8;
/// `FileSystemError.Unsupported`, `ProcessError.Unsupported`.
pub const STATUS_UNSUPPORTED: u8 = 9;
/// `IoError.Closed`, `FileSystemError.Closed`.
pub const STATUS_CLOSED: u8 = 10;
/// `IoError.Failed`, `FileSystemError.Failed`: the diagnostic text comes back through the call's `message` out-pointer.
pub const STATUS_FAILED: u8 = 11;
/// `IoError.Unavailable`.
pub const STATUS_UNAVAILABLE: u8 = 12;
/// `CommandError.Timeout`.
pub const STATUS_TIMEOUT: u8 = 13;
/// `CommandError.OutputLimit`.
pub const STATUS_OUTPUT_LIMIT: u8 = 14;
/// `TerminalError.NotTerminal`: a standard stream is redirected.
pub const STATUS_NOT_TERMINAL: u8 = 15;
/// Success with no value (`Ok(none)`): end of stream or an absent optional result.
pub const STATUS_NONE: u8 = 16;
/// `TerminalError.Busy`: another raw terminal holds the terminal.
pub const STATUS_BUSY: u8 = 17;

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

/// One line-table entry (`LineTable`), sorted by `pc` across the whole table. `pc` is the START of
/// a code range; the range extends to the next entry. A fault frame's line is the entry with the
/// greatest `pc` that is `<=` (return address - 1) and `>=` the function's address.
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
    /// Only read when `abi_version >= 3`: one `u32` per line entry, the inlining scope
    /// of that range (0 = the function itself, else one plus an index into `scopes`).
    pub line_scopes: *const u32,
    pub scopes: *const ScopeEntry,
    pub scope_count: usize,
}

/// One inlined callee, shown as its own fault-trace frame (`abi_version >= 3`).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ScopeEntry {
    pub name_off: u32,
    /// Offset of the callee's file path, or `u32::MAX` when unknown.
    pub file_off: u32,
    /// Enclosing scope (0 = the physical function).
    pub parent: u32,
    /// Line of the inlined call inside the enclosing scope.
    pub call_line: u32,
}
pub const SCOPE_ENTRY_SIZE: usize = 16;

/// First `Tables::abi_version` that carries `line_scopes` and `scopes`.
pub const TABLES_WITH_SCOPES: u32 = 3;

// SAFETY: the table is plain read-only data emitted by the compiler.
unsafe impl Sync for Tables {}

/// Names of the data symbols generated code reads or writes directly.
pub mod symbols {
    /// `usize`: lowest stack address recursive calls may reach (0 = no limit). Inline protocol:
    /// on entry to a recursive function compare the stack pointer against it and call
    /// `msrt_fault_depth` when below.
    pub const STACK_LIMIT: &str = "msrt_stack_limit";
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
        assert_eq!(offset_of!(StrVal, ptr), STR_PTR_OFFSET);
        assert_eq!(offset_of!(StrVal, tagged), STR_LEN_OFFSET);
        assert_eq!(size_of::<StrVal>(), STR_SIZE);
        assert_eq!(offset_of!(OptStr, value), OPT_STR_VALUE_OFFSET);
        assert_eq!(size_of::<OptStr>(), OPT_STR_SIZE);
        assert_eq!(offset_of!(VecVal, ptr), VEC_PTR_OFFSET);
        assert_eq!(offset_of!(VecVal, len), VEC_LEN_OFFSET);
        assert_eq!(offset_of!(VecVal, cap), VEC_CAP_OFFSET);
        assert_eq!(size_of::<VecVal>(), VEC_SIZE);
        assert_eq!(offset_of!(MapVal, len), MAP_LEN_OFFSET);
        assert_eq!(size_of::<MapVal>(), MAP_SIZE);
        assert_eq!(size_of::<TypeDesc>(), DESC_SIZE);
        assert_eq!(offset_of!(TypeDesc, inner0), DESC_INNER0_OFFSET);
        assert_eq!(offset_of!(TypeDesc, inner1), DESC_INNER1_OFFSET);
        assert_eq!(offset_of!(TypeDesc, copy), DESC_COPY_OFFSET);
        assert_eq!(offset_of!(Closure, code), CLOSURE_CODE_OFFSET);
        assert_eq!(size_of::<Closure>(), CLOSURE_CAPTURE_OFFSET);
        assert_eq!(size_of::<OptInt>(), OPT_INT_SIZE);
        assert_eq!(offset_of!(OptInt, value), OPT_SCALAR_VALUE_OFFSET_8);
        assert_eq!(offset_of!(OptFloat, value), OPT_SCALAR_VALUE_OFFSET_8);
        assert_eq!(offset_of!(OptBool, value), OPT_BOOL_VALUE_OFFSET);
        assert_eq!(size_of::<FatPtr>(), FATPTR_SIZE);
        assert_eq!(offset_of!(TypeDesc, drop), DESC_DROP_OFFSET);
        assert_eq!(offset_of!(TypeDesc, eq), DESC_EQ_OFFSET);
        assert_eq!(offset_of!(TypeDesc, hash), DESC_HASH_OFFSET);
        assert_eq!(size_of::<FuncEntry>(), FUNC_ENTRY_SIZE);
        assert_eq!(size_of::<LineEntry>(), LINE_ENTRY_SIZE);
        assert_eq!(size_of::<ScopeEntry>(), SCOPE_ENTRY_SIZE);
        assert_eq!(size_of::<Tables>(), 80);
        assert_eq!(size_of::<usize>(), 8, "64-bit targets only");
    }
}
