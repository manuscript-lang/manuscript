//! The public C ABI of `ms_abi.h`: what a user `extern fn` shim may call. Every entry point is
//! exported under a versioned name (`ms_string_new_v1`), and the header maps the plain name to
//! it, so a shim built against another version fails to link.
//!
//! These functions run on the isolate thread that called into the shim. Strings and bytes
//! handed out in an `ms_value` are copies in system memory (`malloc`), freed by
//! `ms_value_free`, so the shim may keep them past the call.

use crate::desc::{msrt_desc_bool, msrt_desc_bytes, msrt_desc_string};
use crate::fault::fault_fmt;
use crate::obj::{new_obj, release, retain};
use crate::sys::{free, malloc};
use crate::vec::{bytes_from, msrt_bytes_drop, push};
use core::ffi::{c_char, c_void};
use ms_rt_abi::{
    ELEM_BOOL, ELEM_BYTES, ELEM_FLOAT32, ELEM_FLOAT64, ELEM_INT8, ELEM_INT16, ELEM_INT32,
    ELEM_INT64, ELEM_OBJECT, ELEM_STRING, ELEM_UINT8, ELEM_UINT16, ELEM_UINT32, ELEM_UINT64,
    KIND_POD, KIND_SHARED, ListRef, NATIVE_OBJECT_DROP_OFFSET, NATIVE_OBJECT_PAYLOAD_OFFSET, Obj,
    StrVal, TypeDesc, VALUE_BOOL, VALUE_BYTES, VALUE_FLOAT, VALUE_INT, VALUE_OBJECT, VALUE_STRING,
    VALUE_UINT, VALUE_UNIT, Value, ValueAs, ValueBuf, VecVal,
};

/// A shim's object drop entry: called with the payload when the last reference goes.
type PayloadDrop = unsafe extern "C" fn(payload: *mut c_void);

const fn pod(size: u32) -> TypeDesc {
    TypeDesc {
        size,
        align: size,
        kind: KIND_POD,
        reserved: 0,
        inner0: core::ptr::null(),
        inner1: core::ptr::null(),
        drop: None,
        copy: None,
        eq: None,
        hash: None,
    }
}
static POD1: TypeDesc = pod(1);
static POD2: TypeDesc = pod(2);
static POD4: TypeDesc = pod(4);
static POD8: TypeDesc = pod(8);
static OBJECT: TypeDesc = TypeDesc {
    kind: KIND_SHARED,
    ..pod(8)
};

/// The Manuscript name of a list element type, for fault messages.
fn elem_name(elem: u64) -> &'static str {
    match elem {
        ELEM_INT8 => "Int8",
        ELEM_INT16 => "Int16",
        ELEM_INT32 => "Int32",
        ELEM_INT64 => "Int",
        ELEM_UINT8 => "UInt8",
        ELEM_UINT16 => "UInt16",
        ELEM_UINT32 => "UInt32",
        ELEM_UINT64 => "UInt64",
        ELEM_FLOAT32 => "Float32",
        ELEM_FLOAT64 => "Float",
        ELEM_BOOL => "Bool",
        ELEM_STRING => "String",
        ELEM_BYTES => "Bytes",
        ELEM_OBJECT => "an extern type",
        _ => "an unknown type",
    }
}

fn kind_name(kind: u32) -> &'static str {
    match kind {
        VALUE_UNIT => "MS_UNIT",
        VALUE_BOOL => "MS_BOOL",
        VALUE_INT => "MS_INT",
        VALUE_UINT => "MS_UINT",
        VALUE_FLOAT => "MS_FLOAT",
        VALUE_STRING => "MS_STRING",
        VALUE_BYTES => "MS_BYTES",
        VALUE_OBJECT => "MS_OBJECT",
        8 => "MS_LIST",
        9 => "MS_FN",
        _ => "an unknown kind",
    }
}

/// The descriptor of a list element type.
fn elem_desc(elem: u64) -> &'static TypeDesc {
    match elem {
        ELEM_STRING => &msrt_desc_string,
        ELEM_BYTES => &msrt_desc_bytes,
        ELEM_OBJECT => &OBJECT,
        ELEM_BOOL => &msrt_desc_bool,
        _ => match (elem >> 8) & 0xff {
            1 => &POD1,
            2 => &POD2,
            4 => &POD4,
            _ => &POD8,
        },
    }
}

/// A `malloc` copy of `data` (NULL for no bytes).
fn system_copy(data: &[u8]) -> *const u8 {
    if data.is_empty() {
        return core::ptr::null();
    }
    // SAFETY: a fresh block of `data.len()` bytes.
    unsafe {
        let p = malloc(data.len()) as *mut u8;
        if p.is_null() {
            fault_fmt(format_args!(
                "out of memory copying {} bytes for a native",
                data.len()
            ));
        }
        core::ptr::copy_nonoverlapping(data.as_ptr(), p, data.len());
        p
    }
}

/// The bytes of a borrowed buffer.
///
/// # Safety
/// `data..data+len` must be readable when `len` is non-zero.
unsafe fn bytes<'a>(data: *const u8, len: usize) -> &'a [u8] {
    if len == 0 {
        &[]
    } else {
        // SAFETY: caller contract.
        unsafe { core::slice::from_raw_parts(data, len) }
    }
}

/// `char *ms_str_cstring(const ms_str *s)`: a `malloc` NUL-terminated copy, or NULL when the
/// string contains a NUL byte.
///
/// # Safety
/// `s` must be a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_str_cstring_v1(s: *const StrVal) -> *mut c_char {
    // SAFETY: caller contract.
    let data = unsafe { bytes((*s).data(), (*s).len()) };
    if data.contains(&0) {
        return core::ptr::null_mut();
    }
    // SAFETY: a fresh block of `len + 1` bytes.
    unsafe {
        let p = malloc(data.len() + 1) as *mut u8;
        if p.is_null() {
            return core::ptr::null_mut();
        }
        core::ptr::copy_nonoverlapping(data.as_ptr(), p, data.len());
        *p.add(data.len()) = 0;
        p as *mut c_char
    }
}

/// `void ms_string_new(const uint8_t *data, size_t len, ms_str *out)`: replaces the string in
/// `out` with a copy of the bytes. Invalid UTF-8 faults.
///
/// # Safety
/// `data..data+len` readable; `out` holds a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_string_new_v1(data: *const u8, len: usize, out: *mut StrVal) {
    // SAFETY: caller contract.
    let data = unsafe { bytes(data, len) };
    if core::str::from_utf8(data).is_err() {
        fault_fmt(format_args!(
            "ms_string_new received {len} bytes that are not UTF-8; use ms_bytes_new for binary data"
        ));
    }
    // SAFETY: `out` holds a live string, which the new one replaces.
    unsafe {
        crate::string::release(&*out);
        crate::string::from_bytes(data).write_to(out);
    }
}

/// `void ms_bytes_new(const uint8_t *data, size_t len, ms_bytes *out)`: replaces the bytes in
/// `out` with a copy.
///
/// # Safety
/// `data..data+len` readable; `out` holds live bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_bytes_new_v1(data: *const u8, len: usize, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        msrt_bytes_drop(out);
        bytes_from(bytes(data, len), out);
    }
}

/// `void ms_value_free(ms_value *v)`: frees the copy a string or bytes value holds.
///
/// # Safety
/// `v` came from `ms_list_get` (or is a value whose buffer the shim does not own: then it
/// must not be passed here).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_value_free_v1(v: *mut Value) {
    // SAFETY: caller contract.
    unsafe {
        if matches!((*v).kind, VALUE_STRING | VALUE_BYTES) {
            free((*v).as_.buf.data as *mut c_void);
        }
        (*v).kind = VALUE_UNIT;
        (*v).as_.u = 0;
    }
}

/// `size_t ms_list_len(const ms_list *l)`.
///
/// # Safety
/// `l` is a list a Manuscript call lent.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_list_len_v1(l: *const ListRef) -> usize {
    // SAFETY: caller contract.
    unsafe { (*(*l).vec).len }
}

/// `ms_kind ms_list_kind(const ms_list *l)`: the kind of the elements.
///
/// # Safety
/// `l` is a list a Manuscript call lent.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_list_kind_v1(l: *const ListRef) -> u32 {
    // SAFETY: caller contract.
    unsafe { ((*l).elem & 0xff) as u32 }
}

/// `ms_value ms_list_get(const ms_list *l, size_t i)`. Integers widen to `int64_t` or
/// `uint64_t` and floats to `double`; strings and bytes are `malloc` copies; objects borrowed.
///
/// # Safety
/// `l` is a list a Manuscript call lent.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_list_get_v1(l: *const ListRef, i: usize) -> Value {
    // SAFETY: caller contract; `i` is checked against the length.
    unsafe {
        let (v, elem) = (&*(*l).vec, (*l).elem);
        if i >= v.len {
            fault_fmt(format_args!(
                "ms_list_get index {i} is out of range for a list of {} elements",
                v.len
            ));
        }
        let size = elem_desc(elem).size as usize;
        let at = v.ptr.add(i * size);
        let kind = (elem & 0xff) as u32;
        let as_ = match elem {
            ELEM_INT8 => ValueAs {
                i: *(at as *const i8) as i64,
            },
            ELEM_INT16 => ValueAs {
                i: *(at as *const i16) as i64,
            },
            ELEM_INT32 => ValueAs {
                i: *(at as *const i32) as i64,
            },
            ELEM_INT64 => ValueAs {
                i: *(at as *const i64),
            },
            ELEM_UINT8 => ValueAs { u: *at as u64 },
            ELEM_UINT16 => ValueAs {
                u: *(at as *const u16) as u64,
            },
            ELEM_UINT32 => ValueAs {
                u: *(at as *const u32) as u64,
            },
            ELEM_UINT64 => ValueAs {
                u: *(at as *const u64),
            },
            ELEM_FLOAT32 => ValueAs {
                f: *(at as *const f32) as f64,
            },
            ELEM_FLOAT64 => ValueAs {
                f: *(at as *const f64),
            },
            ELEM_BOOL => ValueAs { b: *at != 0 },
            ELEM_STRING => {
                let s = &*(at as *const StrVal);
                let data = bytes(s.data(), s.len());
                ValueAs {
                    buf: ValueBuf {
                        data: system_copy(data),
                        len: data.len(),
                    },
                }
            }
            ELEM_BYTES => {
                let b = &*(at as *const VecVal);
                let data = bytes(b.ptr, b.len);
                ValueAs {
                    buf: ValueBuf {
                        data: system_copy(data),
                        len: data.len(),
                    },
                }
            }
            _ => ValueAs {
                ptr: *(at as *const *mut u8),
            },
        };
        Value { kind, as_ }
    }
}

/// Whether `x` fits an integer element of `bytes` bytes.
fn signed_fits(x: i64, bytes: u64) -> bool {
    bytes >= 8 || (-(1i64 << (bytes * 8 - 1))..1i64 << (bytes * 8 - 1)).contains(&x)
}

fn unsigned_fits(x: u64, bytes: u64) -> bool {
    bytes >= 8 || x < 1u64 << (bytes * 8)
}

/// `void ms_list_push(ms_list *out, const ms_value *v)`: appends a copy of `v`. A value of
/// another kind, or an integer out of the element's range, faults naming both.
///
/// # Safety
/// `l` is a list result a Manuscript call lent; `v` is readable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_list_push_v1(l: *mut ListRef, v: *const Value) {
    // SAFETY: caller contract.
    unsafe {
        let (list, elem, v) = (&mut *(*l).vec, (*l).elem, &*v);
        let width = (elem >> 8) & 0xff;
        if v.kind as u64 != elem & 0xff {
            fault_fmt(format_args!(
                "ms_list_push received {} for a List[{}]",
                kind_name(v.kind),
                elem_name(elem)
            ));
        }
        let out_of_range = match v.kind {
            VALUE_INT => !signed_fits(v.as_.i, width),
            VALUE_UINT => !unsigned_fits(v.as_.u, width),
            _ => false,
        };
        if out_of_range {
            let shown: i128 = if v.kind == VALUE_INT {
                v.as_.i as i128
            } else {
                v.as_.u as i128
            };
            fault_fmt(format_args!(
                "ms_list_push value {shown} is out of range for a List[{}]",
                elem_name(elem)
            ));
        }
        let d = elem_desc(elem);
        let mut slot = [0u64; 3];
        let at = slot.as_mut_ptr() as *mut u8;
        match elem {
            ELEM_FLOAT32 => *(at as *mut f32) = v.as_.f as f32,
            ELEM_FLOAT64 => *(at as *mut f64) = v.as_.f,
            ELEM_BOOL => *at = v.as_.b as u8,
            ELEM_STRING => {
                let data = bytes(v.as_.buf.data, v.as_.buf.len);
                if core::str::from_utf8(data).is_err() {
                    fault_fmt(format_args!(
                        "ms_list_push received {} bytes that are not UTF-8 for a List[String]",
                        data.len()
                    ));
                }
                crate::string::from_bytes(data).write_to(at as *mut StrVal);
            }
            ELEM_BYTES => bytes_from(bytes(v.as_.buf.data, v.as_.buf.len), at as *mut VecVal),
            ELEM_OBJECT => {
                if v.as_.ptr.is_null() {
                    fault_fmt(format_args!("ms_list_push received a NULL object"));
                }
                retain(v.as_.ptr as *mut Obj);
                *(at as *mut *mut u8) = v.as_.ptr;
            }
            // Integers: the low bytes of the little-endian word.
            _ => *(at as *mut u64) = v.as_.u,
        }
        push(list, d, at);
    }
}

/// The drop entry of an object from `ms_object_new`: runs the shim's drop, then frees.
unsafe extern "C" fn native_object_drop(o: *mut Obj) {
    // SAFETY: `o` was built by `ms_object_new_v1` and its count reached zero.
    unsafe {
        let base = o as *mut u8;
        let drop = *(base.add(NATIVE_OBJECT_DROP_OFFSET) as *const Option<PayloadDrop>);
        if let Some(drop) = drop {
            drop(base.add(NATIVE_OBJECT_PAYLOAD_OFFSET) as *mut c_void);
        }
        crate::alloc::free(base);
    }
}

/// `ms_object *ms_object_new(size_t size, void (*drop)(void *payload))`: an object with `size`
/// zeroed payload bytes, 16-byte aligned, and a count of one.
///
/// # Safety
/// `drop` is null or a function that may be called once with the payload.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_object_new_v1(
    size: usize,
    drop: Option<PayloadDrop>,
) -> *mut Obj {
    let total = NATIVE_OBJECT_PAYLOAD_OFFSET
        .checked_add(size)
        .unwrap_or_else(|| fault_fmt(format_args!("ms_object_new size {size} is too large")));
    // SAFETY: a fresh block of `total` bytes, at least the header and the drop word.
    unsafe {
        let o = new_obj(total, native_object_drop);
        let base = o as *mut u8;
        *(base.add(NATIVE_OBJECT_DROP_OFFSET) as *mut Option<PayloadDrop>) = drop;
        core::ptr::write_bytes(
            base.add(NATIVE_OBJECT_DROP_OFFSET + 8),
            0,
            total - NATIVE_OBJECT_DROP_OFFSET - 8,
        );
        o
    }
}

/// `void *ms_payload(ms_object *o)`.
///
/// # Safety
/// `o` was built by `ms_object_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_payload_v1(o: *mut Obj) -> *mut c_void {
    // SAFETY: the payload follows the header and the drop word.
    unsafe { (o as *mut u8).add(NATIVE_OBJECT_PAYLOAD_OFFSET) as *mut c_void }
}

/// `ms_object *ms_retain(ms_object *o)`: adds a reference and returns `o`.
///
/// # Safety
/// `o` is null or a live object.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_retain_v1(o: *mut Obj) -> *mut Obj {
    // SAFETY: caller contract.
    unsafe { retain(o) };
    o
}

/// `void ms_release(ms_object *o)`: drops a reference.
///
/// # Safety
/// `o` is null or a live object the shim owns a reference to.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_release_v1(o: *mut Obj) {
    // SAFETY: caller contract.
    unsafe { release(o) }
}

/// `void ms_fault(const char *text, size_t len)`: an unrecoverable error, reported and cleaned
/// up like a Manuscript fault.
///
/// # Safety
/// `text..text+len` readable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_fault_v1(text: *const c_char, len: usize) -> ! {
    // SAFETY: caller contract.
    let text = unsafe { bytes(text as *const u8, len) };
    crate::fault::fault(text)
}
