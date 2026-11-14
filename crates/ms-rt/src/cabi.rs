//! The public C ABI of `ms_abi.h`: what a user `extern fn` shim may call. Every entry point is
//! exported under a versioned name (`ms_string_new_v1`), and the header maps the plain name to
//! it, so a shim built against another version fails to link.
//!
//! These functions run on the isolate thread that called into the shim. Strings and bytes
//! handed out in an `ms_value` are copies in system memory (`malloc`), freed by
//! `ms_value_free`, so the shim may keep them past the call.

use crate::desc::{msrt_desc_bool, msrt_desc_bytes, msrt_desc_string};
use crate::fault::fault_fmt;
use crate::obj::{clone_obj, drop_obj, new_obj};
use crate::sys::{free, malloc};
use crate::vec::{bytes_from, msrt_bytes_drop, push};
use core::ffi::{c_char, c_void};
use core::sync::atomic::{AtomicUsize, Ordering};
use ms_rt_abi::{
    CALL_MAX_PARAMS, CLOSURE_CODE_OFFSET, ELEM_BOOL, ELEM_BYTES, ELEM_FLOAT32, ELEM_FLOAT64,
    ELEM_INT8, ELEM_INT16, ELEM_INT32, ELEM_INT64, ELEM_OBJECT, ELEM_STRING, ELEM_UINT8,
    ELEM_UINT16, ELEM_UINT32, ELEM_UINT64, KIND_POD, KIND_SHARED, ListRef,
    NATIVE_OBJECT_DROP_OFFSET, NATIVE_OBJECT_PAYLOAD_OFFSET, Obj, STOP_HOOKS_MAX, StrVal, TypeDesc,
    VALUE_BOOL, VALUE_BYTES, VALUE_FLOAT, VALUE_INT, VALUE_OBJECT, VALUE_STRING, VALUE_UINT,
    VALUE_UNIT, Value, ValueAs, ValueBuf, VecVal,
};

/// `ms_fn` layout: the object header, the closure, the signature word.
const FN_CLOSURE_OFFSET: usize = 16;
const FN_SIG_OFFSET: usize = 24;
const FN_SIZE: usize = 32;

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
        load_value(v.ptr.add(i * size), elem)
    }
}

/// The `ms_value` of the element of type `elem` at `at`: integers widened, strings and bytes as
/// `malloc` copies, objects borrowed.
///
/// # Safety
/// `at` holds a live value of type `elem`.
unsafe fn load_value(at: *const u8, elem: u64) -> Value {
    // SAFETY: caller contract.
    unsafe {
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
        if let Some(m) = mismatch(v, elem) {
            fault_fmt(format_args!(
                "ms_list_push {} for a List[{}]",
                m.show(v),
                elem_name(elem)
            ));
        }
        let mut slot = [0u64; 3];
        let at = slot.as_mut_ptr() as *mut u8;
        store_value(v, elem, at, true);
        push(list, elem_desc(elem), at);
    }
}

/// Why an `ms_value` cannot become a value of an element type.
enum Mismatch {
    Kind,
    Range,
    Utf8,
    Null,
}

impl Mismatch {
    /// The start of a fault message: "received MS_STRING", "value 300 is out of range".
    fn show(&self, v: &Value) -> std::string::String {
        // SAFETY: the member read is the one `v.kind` names.
        unsafe {
            match self {
                Mismatch::Kind => std::format!("received {}", kind_name(v.kind)),
                Mismatch::Range if v.kind == VALUE_INT => {
                    std::format!("value {} is out of range", v.as_.i)
                }
                Mismatch::Range => std::format!("value {} is out of range", v.as_.u),
                Mismatch::Utf8 => {
                    std::format!("received {} bytes that are not UTF-8", v.as_.buf.len)
                }
                Mismatch::Null => "received a NULL object".into(),
            }
        }
    }
}

/// Whether `v` can become a value of type `elem`.
fn mismatch(v: &Value, elem: u64) -> Option<Mismatch> {
    if v.kind as u64 != elem & 0xff {
        return Some(Mismatch::Kind);
    }
    let width = (elem >> 8) & 0xff;
    // SAFETY: the member read is the one `v.kind` names; a buffer is readable by contract.
    unsafe {
        match v.kind {
            VALUE_INT if !signed_fits(v.as_.i, width) => Some(Mismatch::Range),
            VALUE_UINT if !unsigned_fits(v.as_.u, width) => Some(Mismatch::Range),
            VALUE_STRING if core::str::from_utf8(bytes(v.as_.buf.data, v.as_.buf.len)).is_err() => {
                Some(Mismatch::Utf8)
            }
            VALUE_OBJECT if v.as_.ptr.is_null() => Some(Mismatch::Null),
            _ => None,
        }
    }
}

/// Writes a value of type `elem` made from `v`, which [`mismatch`] accepted, at `at`: a string
/// or bytes copy, the number, and an object cloned when the value is `owned` by its new holder
/// (a list element) or the object itself when it is only lent (an argument of `ms_call`).
///
/// # Safety
/// `at` has room for the value (24 bytes suffice); `v`'s buffer is readable.
unsafe fn store_value(v: &Value, elem: u64, at: *mut u8, owned: bool) {
    // SAFETY: caller contract.
    unsafe {
        match elem {
            ELEM_FLOAT32 => *(at as *mut f32) = v.as_.f as f32,
            ELEM_FLOAT64 => *(at as *mut f64) = v.as_.f,
            ELEM_BOOL => *at = v.as_.b as u8,
            ELEM_STRING => crate::string::from_bytes(bytes(v.as_.buf.data, v.as_.buf.len))
                .write_to(at as *mut StrVal),
            ELEM_BYTES => bytes_from(bytes(v.as_.buf.data, v.as_.buf.len), at as *mut VecVal),
            ELEM_OBJECT => {
                let o = v.as_.ptr as *mut Obj;
                *(at as *mut *mut Obj) = if owned { clone_obj(o) } else { o };
            }
            // Integers: the low bytes of the little-endian word.
            _ => *(at as *mut u64) = v.as_.u,
        }
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
        let o = new_obj(total, None, native_object_drop);
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

/// `ms_object *ms_object_clone(ms_object *o)`: an independent copy of `o` through its clone
/// entry; an extern type value has none, so copying one faults.
///
/// # Safety
/// `o` is null or a live object.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_object_clone_v1(o: *mut Obj) -> *mut Obj {
    // SAFETY: caller contract.
    unsafe { clone_obj(o) }
}

/// `void ms_object_drop(ms_object *o)`: drops an object the shim owns.
///
/// # Safety
/// `o` is null or a live object the shim owns.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_object_drop_v1(o: *mut Obj) {
    // SAFETY: caller contract.
    unsafe { drop_obj(o) }
}

/// `void ms_fault(const char *text, size_t len)`: an unrecoverable error, reported and cleaned
/// up like a Manuscript fault.
///
/// # Safety
/// `text..text+len` readable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_fault_v1(text: *const c_char, len: usize) -> ! {
    // SAFETY: caller contract.
    let text = unsafe { bytes(text.cast::<u8>(), len) };
    crate::fault::fault(text)
}

/// The drop entry of an `ms_fn`: drops its closure, then frees.
unsafe extern "C" fn fn_drop(o: *mut Obj) {
    // SAFETY: `o` was built by `msrt_fn_new` and its owner dropped it.
    unsafe {
        let base = o as *mut u8;
        drop_obj(*(base.add(FN_CLOSURE_OFFSET) as *const *mut Obj));
        crate::alloc::free(base);
    }
}

/// The clone entry of an `ms_fn`: a new `ms_fn` over a clone of the closure.
unsafe extern "C" fn fn_clone(o: *mut Obj) -> *mut Obj {
    // SAFETY: `o` is a live `ms_fn`.
    unsafe {
        let base = o as *const u8;
        let closure = clone_obj(*(base.add(FN_CLOSURE_OFFSET) as *const *mut Obj));
        msrt_fn_new(closure, *(base.add(FN_SIG_OFFSET) as *const u64))
    }
}

/// The `ms_fn` generated code passes for a function argument of a user extern: `closure`,
/// which the `ms_fn` owns, takes its arguments from 24-byte cells and puts its result in the
/// cell after the last parameter; `sig` packs the parameter count in its low byte, then one byte
/// per parameter and the result in the top byte, each `kind | width << 4`.
///
/// # Safety
/// `closure` is a live closure of that shape, handed over.
// ms: keeps:closure
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fn_new(closure: *mut Obj, sig: u64) -> *mut Obj {
    // SAFETY: a fresh block with room for the closure and the signature.
    unsafe {
        let o = new_obj(FN_SIZE, Some(fn_clone), fn_drop);
        let base = o as *mut u8;
        *(base.add(FN_CLOSURE_OFFSET) as *mut *mut Obj) = closure;
        *(base.add(FN_SIG_OFFSET) as *mut u64) = sig;
        o
    }
}

/// The element code of one signature byte.
fn sig_elem(byte: u64) -> u64 {
    (byte & 0xf) | (byte >> 4) << 8
}

/// `void ms_call(ms_fn *f, const ms_value *args, size_t count, ms_value *result)`: calls the
/// function with the arguments lent, as every function value is called: a string or bytes is
/// copied in for the call and freed after it, an object is passed as it is and stays the
/// shim's; `result` (may be NULL) receives its value like
/// `ms_list_get` does, with a string or bytes as a `malloc` copy. A wrong count, kind or range
/// faults before the call; a fault in the function is the program's fault.
///
/// # Safety
/// `f` is a live `ms_fn`; `args` holds `count` readable values; `result` is NULL or writable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_call_v1(
    f: *mut Obj,
    args: *const Value,
    count: usize,
    result: *mut Value,
) {
    // SAFETY: caller contract; the closure and its signature come from `msrt_fn_new`.
    unsafe {
        let base = f as *mut u8;
        let sig = *(base.add(FN_SIG_OFFSET) as *const u64);
        let n = (sig & 0xff) as usize;
        if count != n {
            fault_fmt(format_args!(
                "ms_call received {count} arguments for a function of {n} parameters"
            ));
        }
        let args = if n == 0 {
            &[][..]
        } else {
            core::slice::from_raw_parts(args, n)
        };
        let elems: [u64; CALL_MAX_PARAMS] =
            core::array::from_fn(|i| sig_elem((sig >> (8 * (i + 1))) & 0xff));
        for (i, v) in args.iter().enumerate() {
            if let Some(m) = mismatch(v, elems[i]) {
                fault_fmt(format_args!(
                    "ms_call {} for parameter {} of type {}",
                    m.show(v),
                    i + 1,
                    elem_name(elems[i])
                ));
            }
        }
        let mut cells = [[0u64; 3]; CALL_MAX_PARAMS + 1];
        for (i, v) in args.iter().enumerate() {
            store_value(v, elems[i], cells[i].as_mut_ptr() as *mut u8, false);
        }
        let closure = *(base.add(FN_CLOSURE_OFFSET) as *const *mut u8);
        let code: unsafe extern "C-unwind" fn(*mut u8, *mut u8) =
            core::mem::transmute(*(closure.add(CLOSURE_CODE_OFFSET) as *const *const u8));
        // The thunk takes the string and bytes copies out of their cells and drops them; an
        // object stays the shim's (see `ms_lower::external::invoke_thunk`).
        code(closure, cells.as_mut_ptr() as *mut u8);
        let ret = sig >> 56;
        let at = cells[CALL_MAX_PARAMS].as_mut_ptr() as *mut u8;
        let v = if ret == 0 {
            Value {
                kind: VALUE_UNIT,
                as_: ValueAs { u: 0 },
            }
        } else {
            let elem = sig_elem(ret);
            let v = load_value(at, elem);
            match elem {
                ELEM_STRING => crate::string::release(&*(at as *const StrVal)),
                ELEM_BYTES => msrt_bytes_drop(at as *mut VecVal),
                _ => {}
            }
            v
        };
        if result.is_null() {
            let mut v = v;
            ms_value_free_v1(&mut v);
        } else {
            *result = v;
        }
    }
}

/// `ms_fn *ms_fn_clone(ms_fn *f)`: a copy of `f` the shim keeps past the extern call.
///
/// # Safety
/// `f` is a live `ms_fn`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_fn_clone_v1(f: *mut Obj) -> *mut Obj {
    // SAFETY: caller contract.
    unsafe { clone_obj(f) }
}

/// `void ms_fn_drop(ms_fn *f)`: drops a copy from `ms_fn_clone`.
///
/// # Safety
/// `f` is a live `ms_fn` the shim owns.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_fn_drop_v1(f: *mut Obj) {
    // SAFETY: caller contract.
    unsafe { drop_obj(f) }
}

/// The stop hooks `ms_on_stop` registered: a function word (0 for a free slot) and its
/// argument. A signal handler reads them, so they are atomics written in order.
static STOP_HOOKS: [StopHook; STOP_HOOKS_MAX] = [const { StopHook::new() }; STOP_HOOKS_MAX];

struct StopHook {
    func: AtomicUsize,
    arg: AtomicUsize,
}

impl StopHook {
    const fn new() -> StopHook {
        StopHook {
            func: AtomicUsize::new(0),
            arg: AtomicUsize::new(0),
        }
    }
}

/// Runs every stop hook; called once per stop request, from a signal handler or the console
/// control thread.
pub(crate) fn run_stop_hooks() {
    for h in &STOP_HOOKS {
        let func = h.func.load(Ordering::Acquire);
        // 0 is a free slot, 1 one that `ms_on_stop` is filling.
        if func > 1 {
            let arg = h.arg.load(Ordering::Relaxed);
            // SAFETY: `ms_on_stop` stored a function of this type.
            let func: unsafe extern "C" fn(*mut c_void) = unsafe { core::mem::transmute(func) };
            // SAFETY: the shim's contract: async-signal-safe.
            unsafe { func(arg as *mut c_void) };
        }
    }
}

/// `ms_stop_hook *ms_on_stop(void (*fn)(void *arg), void *arg)`: runs `fn(arg)` when a stop is
/// requested; NULL when every slot is taken.
///
/// # Safety
/// `func` is async-signal-safe and may run on any thread until `ms_on_stop_remove`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_on_stop_v1(
    func: unsafe extern "C" fn(*mut c_void),
    arg: *mut c_void,
) -> *mut c_void {
    for (i, h) in STOP_HOOKS.iter().enumerate() {
        // Claim a free slot with a placeholder, publish the argument, then the function.
        if h.func
            .compare_exchange(0, 1, Ordering::Acquire, Ordering::Relaxed)
            .is_ok()
        {
            h.arg.store(arg as usize, Ordering::Relaxed);
            h.func.store(func as usize, Ordering::Release);
            return (i + 1) as *mut c_void;
        }
    }
    core::ptr::null_mut()
}

/// `void ms_on_stop_remove(ms_stop_hook *h)`: removes a hook; NULL is ignored.
///
/// # Safety
/// `h` is NULL or came from `ms_on_stop` and was not removed.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn ms_on_stop_remove_v1(h: *mut c_void) {
    let i = h as usize;
    if (1..=STOP_HOOKS_MAX).contains(&i) {
        STOP_HOOKS[i - 1].func.store(0, Ordering::Release);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::sync::atomic::AtomicU32;

    static RAN: AtomicU32 = AtomicU32::new(0);

    unsafe extern "C" fn count(arg: *mut c_void) {
        RAN.fetch_add(arg.addr() as u32, Ordering::Relaxed);
    }

    #[test]
    fn stop_hooks_run_until_removed() {
        // SAFETY: `count` is async-signal-safe.
        unsafe {
            let a = ms_on_stop_v1(count, core::ptr::without_provenance_mut(2));
            let b = ms_on_stop_v1(count, core::ptr::without_provenance_mut(10));
            assert!(!a.is_null() && !b.is_null() && a != b);
            run_stop_hooks();
            assert_eq!(RAN.load(Ordering::Relaxed), 12);
            ms_on_stop_remove_v1(a);
            run_stop_hooks();
            assert_eq!(RAN.load(Ordering::Relaxed), 22);
            ms_on_stop_remove_v1(b);
            ms_on_stop_remove_v1(core::ptr::null_mut());
            run_stop_hooks();
            assert_eq!(RAN.load(Ordering::Relaxed), 22);
        }
    }

    #[test]
    fn signature_bytes_name_element_types() {
        assert_eq!(sig_elem(VALUE_INT as u64 | 1 << 4), ELEM_INT8);
        assert_eq!(sig_elem(VALUE_UINT as u64 | 8 << 4), ELEM_UINT64);
        assert_eq!(sig_elem(VALUE_FLOAT as u64 | 4 << 4), ELEM_FLOAT32);
        assert_eq!(sig_elem(VALUE_STRING as u64), ELEM_STRING);
    }
}
