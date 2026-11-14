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

extern crate alloc;

#[cfg(test)]
extern crate std;

pub mod record;

/// Bump when any layout or symbol here changes incompatibly.
pub const ABI_VERSION: u32 = 4;

// ---------------------------------------------------------------------------
// Object header
// ---------------------------------------------------------------------------

/// Clone entry of an object header: returns a new object holding an independent copy of
/// the value (a closure's captures deep-copied, a native's payload cloned). Null for a value
/// with one owner, which a program cannot copy; a copy of one is a fault.
pub type CloneFn = unsafe extern "C" fn(*mut Obj) -> *mut Obj;

/// Drop entry of an object header. Called once, when the owner drops the object. The
/// function drops the object's children and then frees its own memory with `msrt_free(obj)`.
pub type DropFn = unsafe extern "C" fn(*mut Obj);

/// The 16-byte header every heap object starts with. An object has one owner: a copy of it
/// goes through `clone`, and the owner's drop goes through `drop`.
#[repr(C)]
pub struct Obj {
    /// Clone protocol entry; null when the value cannot be copied.
    pub clone: Option<CloneFn>,
    /// Drop protocol entry; never null for a live object.
    pub drop: Option<DropFn>,
}

pub const OBJ_CLONE_OFFSET: usize = 0;
pub const OBJ_DROP_OFFSET: usize = 8;
pub const OBJ_HEADER_SIZE: usize = 16;

// ---------------------------------------------------------------------------
// String
// ---------------------------------------------------------------------------

/// `String`: two words in the owner's slot. The second word holds the byte length with the
/// ownership tag in its top two bits; the first points at the UTF-8 bytes, which are followed by
/// one NUL (not counted). A string of at most [`STR_INLINE_MAX`] bytes may instead hold its
/// bytes in the two words themselves.
///
/// A string is an owned value over immutable bytes: copying it allocates and copies the bytes,
/// dropping it frees them. The tag says what the bytes are:
///
/// | top bits | kind | drop | copy |
/// | --- | --- | --- | --- |
/// | `00` | owned allocation starting at `ptr` | frees | duplicates |
/// | `01` | inline: the bytes start at the value's own address, length in bits 56–59 | nothing | bitwise |
/// | `10` | static (a literal or a shared one-byte ASCII string) | nothing | shares |
/// | `11` | view borrowed from another string | nothing | duplicates |
///
/// So `tagged < 1 << 62` (unsigned) is "owned". Read the length with [`StrVal::len`] and the
/// bytes with [`StrVal::data`], which answer for every kind; the raw first word is `ptr_word`.
/// An inline string keeps the bytes past its length zero, so equal inline strings have equal
/// words.
#[repr(C)]
pub struct StrVal {
    /// The bytes' address, or the first eight bytes of an inline string.
    pub ptr_word: *mut u8,
    /// Byte length and tag; read it through [`StrVal::len`].
    pub tagged: usize,
}
/// Tag bit of a string that is not owned (static or view).
pub const STR_BORROWED: usize = 1 << 63;
/// Tag of a static string.
pub const STR_STATIC: usize = STR_BORROWED;
/// Tag of a view.
pub const STR_VIEW: usize = 3 << 62;
/// Tag of an inline string.
pub const STR_INLINE: usize = 1 << 62;
/// Bit position of an inline string's length.
pub const STR_INLINE_LEN_SHIFT: u32 = 56;
/// Longest inline string.
pub const STR_INLINE_MAX: usize = 15;
/// Mask of the byte length in the second word (owned, static and view strings).
pub const STR_LEN_MASK: usize = STR_ASCII - 1;
/// Flag in the second word of an owned, static or view string: every byte is ASCII, so the scalar
/// count is the byte length and a scalar index is a byte index. Set when the string is built;
/// clear means unknown, never non-ASCII. Equal strings may differ in this bit.
pub const STR_ASCII: usize = 1 << 61;

impl StrVal {
    /// An owned string over the allocation at `ptr`.
    #[inline(always)]
    pub const fn owned(ptr: *mut u8, len: usize) -> StrVal {
        StrVal {
            ptr_word: ptr,
            tagged: len,
        }
    }

    /// A static string (never freed, shared on copy).
    #[inline(always)]
    pub const fn literal(ptr: *mut u8, len: usize) -> StrVal {
        StrVal {
            ptr_word: ptr,
            tagged: len | STR_STATIC,
        }
    }

    /// A view of bytes another string owns.
    #[inline(always)]
    pub const fn view(ptr: *mut u8, len: usize) -> StrVal {
        StrVal {
            ptr_word: ptr,
            tagged: len | STR_VIEW,
        }
    }

    /// An inline string holding `bytes` (at most [`STR_INLINE_MAX`] of them).
    #[inline(always)]
    pub fn inline(bytes: &[u8]) -> StrVal {
        debug_assert!(bytes.len() <= STR_INLINE_MAX);
        StrVal::from_bits(pack(bytes), bytes.len())
    }

    /// An inline string of `len` bytes whose little-endian bits are `bits` (zero past `len`).
    #[inline(always)]
    pub fn from_bits(bits: u128, len: usize) -> StrVal {
        StrVal {
            ptr_word: bits as u64 as usize as *mut u8,
            tagged: (bits >> 64) as u64 as usize | STR_INLINE | (len << STR_INLINE_LEN_SHIFT),
        }
    }

    /// The bytes of an inline string as little-endian bits (zero past the length).
    #[inline(always)]
    pub fn inline_bits(&self) -> u128 {
        let hi = self.tagged & ((1 << STR_INLINE_LEN_SHIFT) - 1);
        (self.ptr_word as usize as u128) | ((hi as u128) << 64)
    }

    /// Whether the string holds its bytes inline.
    #[inline(always)]
    pub const fn is_inline(&self) -> bool {
        self.tagged >> 62 == 1
    }

    /// Byte length.
    #[inline(always)]
    pub const fn len(&self) -> usize {
        if self.is_inline() {
            (self.tagged >> STR_INLINE_LEN_SHIFT) & 15
        } else {
            self.tagged & STR_LEN_MASK
        }
    }

    /// The first byte. For an inline string it is the value's own address, so the pointer is
    /// good only while the value stays where it is.
    #[inline(always)]
    pub fn data(&self) -> *const u8 {
        if self.is_inline() {
            self as *const StrVal as *const u8
        } else {
            self.ptr_word
        }
    }

    /// Whether the string is flagged as all ASCII (see [`STR_ASCII`]); inline strings are not
    /// flagged and are checked by their bits instead.
    #[inline(always)]
    pub const fn flagged_ascii(&self) -> bool {
        !self.is_inline() && self.tagged & STR_ASCII != 0
    }

    /// This string flagged as all ASCII; the caller has checked the bytes. Not for inline strings.
    #[inline(always)]
    pub const fn with_ascii(mut self) -> StrVal {
        self.tagged |= STR_ASCII;
        self
    }

    /// Whether the string has no bytes.
    #[inline(always)]
    pub const fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Whether dropping the string frees an allocation (owned: not inline, static or a view).
    #[inline(always)]
    pub const fn owns(&self) -> bool {
        self.tagged < STR_INLINE
    }

    /// Whether the string is static: copies share it.
    #[inline(always)]
    pub const fn is_static(&self) -> bool {
        self.tagged >> 62 == 2
    }

    /// Whether a copy is the same two words (static or inline).
    #[inline(always)]
    pub const fn copies_bitwise(&self) -> bool {
        (self.tagged >> 62).wrapping_sub(1) < 2
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
            ptr_word: self.ptr_word,
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
            core::ptr::write_volatile(&raw mut (*out).ptr_word, self.ptr_word);
            core::ptr::write_volatile(&raw mut (*out).tagged, self.tagged);
        }
    }
}
/// Up to 16 bytes as little-endian bits, zero past the end, without a call to `memcpy`.
#[inline(always)]
pub fn pack(b: &[u8]) -> u128 {
    let n = b.len();
    debug_assert!(n <= 16);
    let p = b.as_ptr();
    // SAFETY: every read lies inside `b`.
    unsafe {
        let r64 = |at: usize| (p.add(at) as *const u64).read_unaligned() as u128;
        let r32 = |at: usize| (p.add(at) as *const u32).read_unaligned() as u128;
        if n >= 8 {
            let tail = if n > 8 {
                r64(n - 8) >> (8 * (16 - n))
            } else {
                0
            };
            r64(0) | (tail << 64)
        } else if n >= 4 {
            r32(0) | (r32(n - 4) << (8 * (n - 4)))
        } else if n > 0 {
            let at = |i: usize| (*p.add(i) as u128) << (8 * i);
            at(0) | at(n / 2) | at(n - 1)
        } else {
            0
        }
    }
}

pub const STR_PTR_OFFSET: usize = 0;
pub const STR_LEN_OFFSET: usize = 8;
pub const STR_SIZE: usize = 16;

/// Distance between consecutive entries of the shared one-character ASCII strings (`msrt_ascii_chars`).
pub const ASCII_CHAR_STRIDE: usize = 2;

/// `String?`: the string itself (16 bytes); none is a static empty string with a null
/// `ptr`, which no present string has (an inline string may have a zero first word, but not the
/// static tag), so dropping or copying none does nothing.
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
            ptr_word: core::ptr::null_mut(),
            tagged: STR_STATIC,
        },
    };

    /// Whether a string is present.
    pub fn is_some(&self) -> bool {
        (self.value.ptr_word as usize | (self.value.tagged ^ STR_STATIC)) != 0
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

/// `Map[K, V]` and `Set[T]`: seven words. Insertion ordered: `slots` is an
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
    /// Static creator key descriptor, or null for descriptor-neutral native maps.
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
/// Slot holds a nullable pointer to an object with an `Obj` header (closures, handle
/// objects...). Copy calls the header's clone entry, drop its drop entry.
/// `eq`/`hash` are called when present, else identity.
pub const KIND_SHARED: u32 = 5;
/// Plain bits without ownership (scalars, records of scalars, inline `Int?`).
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
/// Duplicates the value in `src` into uninitialised `dst` (`.clone()`): every part is deep
/// copied, objects through their clone entry.
pub type SlotCopyFn = unsafe extern "C" fn(src: *const u8, dst: *mut u8);
/// Equality of two slots; returns 0 or 1.
pub type SlotEqFn = unsafe extern "C" fn(a: *const u8, b: *const u8) -> u8;
/// Hash of a slot. Equal values must hash equally.
pub type SlotHashFn = unsafe extern "C" fn(slot: *const u8) -> i64;

/// The presence byte that precedes the value of a flattened optional (`has_x: HasRaw, x: T`). It is
/// the C byte `u8`; the distinct type is the declaration lowering reads the role from.
#[repr(transparent)]
#[derive(Clone, Copy)]
pub struct HasRaw(pub u8);

impl HasRaw {
    /// Whether the optional is present.
    pub fn is_set(self) -> bool {
        self.0 != 0
    }
}

/// The trailing nullable `*mut StrVal` where a fallible native stores the text of a `Failed`
/// status. It is that pointer in C; the distinct type is the declaration lowering reads the role
/// from.
#[repr(transparent)]
#[derive(Clone, Copy)]
pub struct ErrSlot(pub *mut StrVal);

/// The slot descriptor of a list's or set's element type. A runtime function declares this role by
/// taking the alias; lowering reads the role from the declared parameter type, not its name.
pub type ElemDesc = *const TypeDesc;
/// The descriptor of a generic value moved into or out of the runtime (promise, pipe and cell values).
pub type ValueDesc = *const TypeDesc;
/// The slot descriptor of a map's or set's key type.
pub type KeyDesc = *const TypeDesc;
/// The slot descriptor of a map's value type (absent for a set).
pub type ValDesc = *const TypeDesc;

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

/// `Int?` and other 8-byte scalars: `{ present, value }`, 16 bytes.
#[repr(C)]
pub struct OptInt {
    pub present: u8,
    pub value: i64,
}
/// `Float?`.
#[repr(C)]
pub struct OptFloat {
    pub present: u8,
    pub value: f64,
}
/// `Bool?`.
#[repr(C)]
pub struct OptBool {
    pub present: u8,
    pub value: u8,
}
pub const OPT_SCALAR_VALUE_OFFSET_8: usize = 8;
pub const OPT_BOOL_VALUE_OFFSET: usize = 1;
pub const OPT_INT_SIZE: usize = 16;

/// Function value (heap object with one owner): header, code pointer, then captured values chosen by the
/// compiler. Its clone entry deep-copies the captures. Calling convention of `code` is `extern "C" fn(closure: *mut Closure, args...)`.
#[repr(C)]
pub struct Closure {
    pub hdr: Obj,
    pub code: *const u8,
}
pub const CLOSURE_CODE_OFFSET: usize = 16;
/// Offset of the first capture in a closure object.
pub const CLOSURE_CAPTURES_OFFSET: usize = 24;
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
/// `"EINVAL"`.
pub const STATUS_INVALID_INPUT: u8 = 1;
/// `"ERANGE"`.
pub const STATUS_OUT_OF_RANGE: u8 = 2;
/// `"EOVERFLOW"`.
pub const STATUS_LIMIT_EXCEEDED: u8 = 3;
/// `"EBADMSG"`.
pub const STATUS_INVALID_DATA: u8 = 4;
/// `"ENOENT"`.
pub const STATUS_NOT_FOUND: u8 = 5;
/// `"EEXIST"`.
pub const STATUS_ALREADY_EXISTS: u8 = 6;
/// Directory not empty; surfaces as `"EIO"` with the text in `details`.
pub const STATUS_NOT_EMPTY: u8 = 7;
/// `"EACCES"`.
pub const STATUS_PERMISSION_DENIED: u8 = 8;
/// `"ENOTSUP"`.
pub const STATUS_UNSUPPORTED: u8 = 9;
/// `"EBADF"`.
pub const STATUS_CLOSED: u8 = 10;
/// `"EIO"`: the diagnostic text comes back through the call's `message` out-pointer.
pub const STATUS_FAILED: u8 = 11;
/// `"EAGAIN"`.
pub const STATUS_UNAVAILABLE: u8 = 12;
/// `"ETIMEDOUT"`.
pub const STATUS_TIMEOUT: u8 = 13;
/// Process output limit exceeded; surfaces as `"EOVERFLOW"`.
pub const STATUS_OUTPUT_LIMIT: u8 = 14;
/// A standard stream is redirected.
pub const STATUS_NOT_TERMINAL: u8 = 15;
/// Success with no value (`Ok(none)`): end of stream or an absent optional result.
pub const STATUS_NONE: u8 = 16;
/// Another raw terminal holds the terminal.
pub const STATUS_BUSY: u8 = 17;
/// A credential or tag did not verify; surfaces as `"EAUTH"` ("authentication failed").
pub const STATUS_AUTHENTICATION_FAILED: u8 = 18;

// ---------------------------------------------------------------------------
// The public C ABI of `include/ms_abi.h` (user `extern fn` shims)
// ---------------------------------------------------------------------------

/// Offset of the payload in an object from `ms_object_new`: the header, the shim's drop
/// entry, then padding to 16-byte alignment.
pub const NATIVE_OBJECT_PAYLOAD_OFFSET: usize = 32;
/// Offset of the shim's drop entry (`void (*)(void *payload)`, may be null).
pub const NATIVE_OBJECT_DROP_OFFSET: usize = 16;

/// `ms_kind`: the kind of an `ms_value`.
pub const VALUE_UNIT: u32 = 0;
pub const VALUE_BOOL: u32 = 1;
pub const VALUE_INT: u32 = 2;
pub const VALUE_UINT: u32 = 3;
pub const VALUE_FLOAT: u32 = 4;
pub const VALUE_STRING: u32 = 5;
pub const VALUE_BYTES: u32 = 6;
pub const VALUE_OBJECT: u32 = 7;
pub const VALUE_LIST: u32 = 8;
pub const VALUE_FN: u32 = 9;

/// Element type of a `List[T]` crossing to a shim. The low byte is the `ms_kind` of the
/// element; the next byte is its size in bytes for integers and floats (0 otherwise).
pub const ELEM_INT8: u64 = VALUE_INT as u64 | 1 << 8;
pub const ELEM_INT16: u64 = VALUE_INT as u64 | 2 << 8;
pub const ELEM_INT32: u64 = VALUE_INT as u64 | 4 << 8;
pub const ELEM_INT64: u64 = VALUE_INT as u64 | 8 << 8;
pub const ELEM_UINT8: u64 = VALUE_UINT as u64 | 1 << 8;
pub const ELEM_UINT16: u64 = VALUE_UINT as u64 | 2 << 8;
pub const ELEM_UINT32: u64 = VALUE_UINT as u64 | 4 << 8;
pub const ELEM_UINT64: u64 = VALUE_UINT as u64 | 8 << 8;
pub const ELEM_FLOAT32: u64 = VALUE_FLOAT as u64 | 4 << 8;
pub const ELEM_FLOAT64: u64 = VALUE_FLOAT as u64 | 8 << 8;
pub const ELEM_BOOL: u64 = VALUE_BOOL as u64 | 1 << 8;
pub const ELEM_STRING: u64 = VALUE_STRING as u64;
pub const ELEM_BYTES: u64 = VALUE_BYTES as u64;
pub const ELEM_OBJECT: u64 = VALUE_OBJECT as u64;

/// `ms_list`: what a shim receives for a `List[T]` parameter or result. Generated code builds
/// it on the stack around the list value; the shim sees an opaque pointer.
#[repr(C)]
pub struct ListRef {
    pub vec: *mut VecVal,
    /// One of the `ELEM_*` constants.
    pub elem: u64,
}
pub const LIST_REF_VEC_OFFSET: usize = 0;
pub const LIST_REF_ELEM_OFFSET: usize = 8;
pub const LIST_REF_SIZE: usize = 16;

/// The `buf` member of an `ms_value`: a string's or bytes' data.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ValueBuf {
    pub data: *const u8,
    pub len: usize,
}

/// The payload of an `ms_value`.
#[repr(C)]
#[derive(Clone, Copy)]
pub union ValueAs {
    pub b: bool,
    pub i: i64,
    pub u: u64,
    pub f: f64,
    pub buf: ValueBuf,
    pub ptr: *mut u8,
}

/// `ms_value`: a tagged value passed to and from `ms_list_get` and `ms_list_push`.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Value {
    /// One of the `VALUE_*` constants.
    pub kind: u32,
    pub as_: ValueAs,
}
/// The most parameters a function passed to a user extern may take (`ms_call`).
pub const CALL_MAX_PARAMS: usize = 6;
/// The most hooks `ms_on_stop` holds at once.
pub const STOP_HOOKS_MAX: usize = 32;
pub const VALUE_AS_OFFSET: usize = 8;
pub const VALUE_SIZE: usize = 24;

// ---------------------------------------------------------------------------
// Faults, call depth, tables
// ---------------------------------------------------------------------------

/// Maximum nested calls of functions in a recursive cycle.
pub const MAX_CALL_DEPTH: i64 = 200_000;
/// Fault frames shown before "... outer frames omitted".
pub const MAX_FAULT_FRAMES: usize = 32;
/// Exit statuses.
pub const EXIT_FAULT: i32 = 67;
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
    /// Function returning the running task's header block (`msrt_isolate_hdr() -> *mut u8`).
    /// Generated code does not call it: every task stack lies inside a [`STACK_REGION`]-aligned
    /// region whose last 16 bytes hold a pointer to the running task's block, which the scheduler
    /// writes before it switches to the task. Code finds the block as
    /// `*((sp & !(STACK_REGION - 1)) + STACK_REGION - 16)`.
    /// Word 0 (`usize`) of the block is the lowest stack address recursive calls may reach on
    /// the task's current stack segment (0 = no limit); the region holds a copy at
    /// [`STACK_LIMIT_CELL`]. On entry to a recursive function compare
    /// the stack pointer against the copy and, when below, call `msrt_task_grow(shim, block)` with the
    /// function's parameters stored at `block` (one 8-byte cell each, then room for its results)
    /// and return the results it leaves there. The runtime runs `shim(block)` on the task's next
    /// segment, a guarded slot that keeps the frame-pointer chain continuous, and faults with the
    /// stack overflow report when the task holds a region's worth of segments.
    pub const ISOLATE_HDR: &str = "msrt_isolate_hdr";
    /// Size and alignment of a stack region: 512 KiB task slots are carved from a region, and
    /// the main task's stack is a region of its own.
    pub const STACK_REGION: i64 = 256 << 20;
    /// Distance from the end of a stack region to the word that holds the running stack
    /// segment's recursion limit (the block's word 0, copied there so the check is one load):
    /// `*((sp & !(STACK_REGION - 1)) + STACK_REGION - STACK_LIMIT_CELL)`. The runtime writes it
    /// beside the block's address and whenever the limit or the segment changes.
    pub const STACK_LIMIT_CELL: i64 = 8;
    /// How far above the recursion limit the drop glue of recursive data starts to count its
    /// nesting (`ms_rt::dropq`): shallower than this it recurses without any runtime call, and
    /// below it a nest of at most `LIMIT` drops fits in the headroom.
    pub const DEEP_DROP_HEADROOM: i64 = 192 << 10;
    /// `u8` at this offset of the block: non-zero when a stop request (SIGINT, SIGTERM) is
    /// pending and not shielded.
    pub const ISOLATE_HDR_CANCEL: i64 = 8;
    /// `u8` at this offset of the block: non-zero while a guard is open on the task.
    pub const ISOLATE_HDR_GUARDED: i64 = 9;
    pub const DESC_INT: &str = "msrt_desc_int";
    pub const DESC_FLOAT: &str = "msrt_desc_float";
    pub const DESC_FLOAT32: &str = "msrt_desc_float32";
    pub const DESC_BOOL: &str = "msrt_desc_bool";
    pub const DESC_STRING: &str = "msrt_desc_string";
    pub const DESC_BYTES: &str = "msrt_desc_bytes";
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{offset_of, size_of};

    /// The C header for `extern fn` shims. Layouts and constants come from this crate, so the
    /// header cannot drift from the runtime; `header_is_current` compares it with
    /// `include/ms_abi.h`.
    fn header() -> std::string::String {
        let mut functions = std::string::String::new();
        for name in FUNCTIONS {
            functions.push_str(&std::format!("#define {name} {name}_v1\n"));
        }
        std::format!(
            r#"/* Generated from crates/ms-rt-abi/src/lib.rs by the `header_is_current` test; do not edit.
 * Regenerate with: MS_UPDATE_HEADER=1 cargo test -p ms-rt-abi header_is_current
 *
 * ms_abi.h: what a C shim behind a Manuscript `extern fn` may use. The signature types and
 * rules are in documentation/core-language/functions/native-functions.md. Call these functions
 * only on the thread that called the shim, while the extern call is running. */
#ifndef MS_ABI_H
#define MS_ABI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {{
#define MS_NORETURN [[noreturn]]
#define MS_STATIC_ASSERT static_assert
#else
#define MS_NORETURN _Noreturn
#define MS_STATIC_ASSERT _Static_assert
#endif

/* ---- 1. Version ---------------------------------------------------------------------- */
/* Every function links under a versioned name (ms_string_new is ms_string_new_v1), so a shim
   built against another version fails to link and names the function it needs. */
#define MS_ABI_VERSION 1
{functions}
/* ---- 2. Status codes ----------------------------------------------------------------- */
typedef enum ms_status {{
    MS_OK = 0, MS_CANCELLED = 1, MS_TIMEOUT = 2, MS_CLOSED = 3, MS_FAULTED = 4,
    MS_WOULD_DEADLOCK = 5, MS_FULL = 6, MS_INVALID = 7
}} ms_status;

/* ---- 3. Strings and bytes ------------------------------------------------------------ */
/* String: a borrowed `const ms_str *` argument, or a trailing `ms_str *out` result. */
typedef struct ms_str {{ void *ptr_word; size_t tagged; }} ms_str;
/* Bytes: a borrowed `const ms_bytes *` argument, or a trailing `ms_bytes *out` result. */
typedef struct ms_bytes {{ uint8_t *ptr; size_t len; size_t cap; }} ms_bytes;
MS_STATIC_ASSERT(sizeof(ms_str) == {str_size}, "ms_str is two words");
MS_STATIC_ASSERT(offsetof(ms_str, tagged) == {str_len}, "ms_str layout");
MS_STATIC_ASSERT(sizeof(ms_bytes) == {vec_size}, "ms_bytes is three words");

#define MS_STR_INLINE_MAX {inline_max}
/* The top two bits of `tagged` are 1 for a string whose bytes are inside the value. */
static inline int ms_str_is_inline(const ms_str *s) {{ return (s->tagged >> 62) == {inline_tag}; }}
static inline size_t ms_str_len(const ms_str *s) {{
    return ms_str_is_inline(s) ? (s->tagged >> {inline_shift}) & {inline_max} : s->tagged & (size_t)0x{str_len_mask:x};
}}
/* The bytes: UTF-8, not NUL-terminated. */
static inline const uint8_t *ms_str_data(const ms_str *s) {{
    return ms_str_is_inline(s) ? (const uint8_t *)s : (const uint8_t *)s->ptr_word;
}}
static inline size_t ms_bytes_len(const ms_bytes *b) {{ return b->len; }}
static inline const uint8_t *ms_bytes_data(const ms_bytes *b) {{ return b->ptr; }}
/* A malloc'd NUL-terminated copy for C APIs that take `const char *`; NULL if the string
   contains a NUL byte. Free it with free(). */
char *ms_str_cstring(const ms_str *s);
/* Replace the string in `out` with a copy of `len` bytes of UTF-8 (other bytes fault). */
void ms_string_new(const uint8_t *data, size_t len, ms_str *out);
/* Replace the bytes in `out` with a copy of `len` bytes. */
void ms_bytes_new(const uint8_t *data, size_t len, ms_bytes *out);

/* ---- 4. Values ----------------------------------------------------------------------- */
typedef struct ms_object ms_object;
typedef struct ms_list ms_list;
typedef enum ms_kind {{
    MS_UNIT = {unit}, MS_BOOL = {bool_}, MS_INT = {int}, MS_UINT = {uint}, MS_FLOAT = {float},
    MS_STRING = {string}, MS_BYTES = {bytes}, MS_OBJECT = {object}, MS_LIST = {list}, MS_FN = {fn_}
}} ms_kind;
typedef union ms_value_as {{
    bool b; int64_t i; uint64_t u; double f;           /* sized types widen               */
    struct {{ const uint8_t *data; size_t len; }} buf;   /* MS_STRING, MS_BYTES             */
    ms_object *object;
}} ms_value_as;
typedef struct ms_value {{ ms_kind kind; ms_value_as as; }} ms_value;
MS_STATIC_ASSERT(sizeof(ms_value) == {value_size}, "ms_value layout");
/* Free the malloc'd copy that a string or bytes value from ms_list_get holds. */
void ms_value_free(ms_value *v);

/* ---- 5. Lists ------------------------------------------------------------------------ */
/* A List[T] argument is a borrowed `const ms_list *`; a List[T] result is a trailing
   `ms_list *out` that starts empty. The list knows its element type: get widens it into an
   ms_value, push checks the kind and the range and faults naming both types. */
size_t   ms_list_len(const ms_list *l);
ms_kind  ms_list_kind(const ms_list *l);
/* Strings and bytes come back as malloc'd copies (ms_value_free); objects are borrowed. */
ms_value ms_list_get(const ms_list *l, size_t i);
/* Appends a copy of `v`; an object is cloned (ms_object_clone). */
void     ms_list_push(ms_list *out, const ms_value *v);

/* ---- 6. Native objects (extern type) ------------------------------------------------- */
/* An extern type value: `size` bytes of zeroed payload, 16-byte aligned, at a stable address,
   with one owner. `drop(payload)`, which may be NULL, runs once when the owner drops it; it may
   free C memory, start a library's asynchronous close and call ms_object_drop, nothing else. */
ms_object *ms_object_new(size_t size, void (*drop)(void *payload));
void      *ms_payload(ms_object *o);
/* An independent copy of an object the shim keeps past the call; a value that cannot be copied
   (an extern type value is one) faults. */
ms_object *ms_object_clone(ms_object *o);
/* Drops an object the shim owns: one it made and did not return, or cloned. */
void       ms_object_drop(ms_object *o);

/* ---- 7. Errors and faults ------------------------------------------------------------ */
/* A fallible extern returns uint8_t: 0 is ok, n is the n-th case of its error type. If any case
   has a `code: Int` field a trailing `int64_t *code_out` follows; if any has `message: String`
   a trailing `ms_str *message_out` follows. Every output arrives holding a valid empty value
   (0, "", an empty list, NULL); the caller reads the fields of the returned case and drops the
   rest. */
/* An unrecoverable error: reported and cleaned up like a Manuscript fault. */
MS_NORETURN void ms_fault(const char *text, size_t len);

/* ---- 8. Calling Manuscript functions ------------------------------------------------- */
/* A function argument (`f: fn(Int) Bool`) is a borrowed `ms_fn *`. Its parameters (at most
   {call_max}) are sized numbers, Bool, String, Bytes or extern types; its result one of those
   but an extern type, or Unit. */
typedef struct ms_fn ms_fn;
/* Calls f on this thread with `count` arguments lent to it, as every function value is called:
   a string or bytes is copied in for the call, an object is passed as it is and stays the
   shim's. An integer must have the kind (MS_INT or MS_UINT) and range of its parameter and a
   string must be UTF-8; anything else faults before the call. `result` (may be NULL) receives the value
   as ms_list_get gives it: strings and bytes are malloc'd copies (ms_value_free). A fault in f
   is a fault of the program; ms_call does not return from it. */
void   ms_call(ms_fn *f, const ms_value *args, size_t count, ms_value *result);
/* A copy of f to keep after the extern call returns, and its drop, on the thread that called
   the shim. */
ms_fn *ms_fn_clone(ms_fn *f);
void   ms_fn_drop(ms_fn *f);

/* ---- 10. Stop requests --------------------------------------------------------------- */
typedef struct ms_stop_hook ms_stop_hook;
/* fn(arg) runs when a stop is requested (SIGINT, SIGTERM, Ctrl-C), from a signal handler or
   another thread, so it may only do async-signal-safe work: set a flag, write to a pipe, call
   uv_async_send. Use it to return from a C call that blocks. NULL when {stop_hooks} hooks are
   set. */
ms_stop_hook *ms_on_stop(void (*fn)(void *arg), void *arg);
void          ms_on_stop_remove(ms_stop_hook *h);

/* Before version 1: the same as ms_string_new on an empty `out`. */
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, ms_str *out);

#ifdef __cplusplus
}}
#endif
#endif
"#,
            str_size = size_of::<StrVal>(),
            str_len = offset_of!(StrVal, tagged),
            vec_size = size_of::<VecVal>(),
            inline_max = STR_INLINE_MAX,
            str_len_mask = STR_LEN_MASK,
            inline_tag = STR_INLINE >> 62,
            inline_shift = STR_INLINE_LEN_SHIFT,
            unit = VALUE_UNIT,
            bool_ = VALUE_BOOL,
            int = VALUE_INT,
            uint = VALUE_UINT,
            float = VALUE_FLOAT,
            string = VALUE_STRING,
            bytes = VALUE_BYTES,
            object = VALUE_OBJECT,
            list = VALUE_LIST,
            fn_ = VALUE_FN,
            value_size = VALUE_SIZE,
            call_max = CALL_MAX_PARAMS,
            stop_hooks = STOP_HOOKS_MAX,
        )
    }

    /// The functions `ms-rt` exports under `<name>_v1`.
    const FUNCTIONS: &[&str] = &[
        "ms_str_cstring",
        "ms_string_new",
        "ms_bytes_new",
        "ms_value_free",
        "ms_list_len",
        "ms_list_kind",
        "ms_list_get",
        "ms_list_push",
        "ms_object_new",
        "ms_payload",
        "ms_object_clone",
        "ms_object_drop",
        "ms_fault",
        "ms_call",
        "ms_fn_clone",
        "ms_fn_drop",
        "ms_on_stop",
        "ms_on_stop_remove",
    ];

    #[test]
    fn header_is_current() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/include/ms_abi.h");
        let want = header();
        if std::env::var_os("MS_UPDATE_HEADER").is_some() {
            std::fs::write(path, &want).expect("write header");
        }
        let have = std::fs::read_to_string(path).expect("read header");
        assert!(
            have == want,
            "include/ms_abi.h is stale; run `MS_UPDATE_HEADER=1 cargo test -p ms-rt-abi header_is_current`"
        );
    }

    #[test]
    fn inline_strings_hold_their_bytes_in_the_value() {
        let src: [u8; 16] = core::array::from_fn(|i| 0xA0 + i as u8);
        for n in 0..=16 {
            let mut want = [0u8; 16];
            want[..n].copy_from_slice(&src[..n]);
            assert_eq!(
                pack(&src[..n]),
                u128::from_le_bytes(want),
                "pack of {n} bytes"
            );
        }
        for n in 0..=STR_INLINE_MAX {
            let s = StrVal::inline(&src[..n]);
            assert!(s.is_inline() && s.copies_bitwise() && !s.owns());
            assert_eq!(s.len(), n);
            // SAFETY: an inline string's bytes are the first `len` bytes of the value.
            let got = unsafe { core::slice::from_raw_parts(s.data(), s.len()) };
            assert_eq!(got, &src[..n]);
            assert_eq!(s.inline_bits(), pack(&src[..n]));
        }
    }

    #[test]
    fn layouts_match_constants() {
        assert_eq!(size_of::<Obj>(), OBJ_HEADER_SIZE);
        assert_eq!(offset_of!(Obj, clone), OBJ_CLONE_OFFSET);
        assert_eq!(offset_of!(Obj, drop), OBJ_DROP_OFFSET);
        assert_eq!(offset_of!(StrVal, ptr_word), STR_PTR_OFFSET);
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
        assert_eq!(offset_of!(ListRef, vec), LIST_REF_VEC_OFFSET);
        assert_eq!(offset_of!(ListRef, elem), LIST_REF_ELEM_OFFSET);
        assert_eq!(size_of::<ListRef>(), LIST_REF_SIZE);
        assert_eq!(offset_of!(Value, as_), VALUE_AS_OFFSET);
        assert_eq!(size_of::<Value>(), VALUE_SIZE);
        assert_eq!(size_of::<usize>(), 8, "64-bit targets only");
    }
}
