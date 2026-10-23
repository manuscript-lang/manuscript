//! Type descriptors: drop, copy, equality and hash of values stored in slots.
use crate::alloc;
use crate::fault;
use crate::global::Global;
use crate::map;
use crate::obj;
use crate::string;
use ms_rt_abi::*;

const fn builtin(size: u32, align: u32, kind: u32) -> TypeDesc {
    TypeDesc {
        size,
        align,
        kind,
        reserved: 0,
        inner0: core::ptr::null(),
        inner1: core::ptr::null(),
        drop: None,
        copy: None,
        eq: None,
        hash: None,
    }
}

#[unsafe(no_mangle)]
pub static msrt_desc_int: TypeDesc = builtin(8, 8, KIND_INT);
#[unsafe(no_mangle)]
pub static msrt_desc_float: TypeDesc = builtin(8, 8, KIND_FLOAT);
#[unsafe(no_mangle)]
pub static msrt_desc_bool: TypeDesc = builtin(1, 1, KIND_BOOL);
#[unsafe(no_mangle)]
pub static msrt_desc_string: TypeDesc = builtin(24, 8, KIND_STRING);
#[unsafe(no_mangle)]
pub static msrt_desc_bytes: TypeDesc = builtin(24, 8, KIND_BYTES);

/// True when a value of this type owns nothing and copies bitwise.
#[inline]
pub fn is_plain(d: &TypeDesc) -> bool {
    match d.kind {
        KIND_INT | KIND_FLOAT | KIND_BOOL | KIND_POD => true,
        KIND_CUSTOM => d.drop.is_none() && d.copy.is_none(),
        _ => false,
    }
}

/// True when dropping a value of this type does nothing.
#[inline]
pub fn needs_no_drop(d: &TypeDesc) -> bool {
    match d.kind {
        KIND_INT | KIND_FLOAT | KIND_BOOL | KIND_POD => true,
        KIND_CUSTOM => d.drop.is_none(),
        _ => false,
    }
}

/// Drops the value in `slot`.
///
/// # Safety
/// `slot` holds a live value described by `d`.
#[inline(always)]
pub unsafe fn slot_drop(d: &TypeDesc, slot: *mut u8) {
    // Plain scalars and PODs own nothing: skip the out-of-line call.
    if matches!(d.kind, KIND_INT | KIND_FLOAT | KIND_BOOL | KIND_POD) {
        return;
    }
    // SAFETY: per the contract of each kind.
    unsafe { slot_drop_owned(d, slot) }
}

#[inline(never)]
unsafe fn slot_drop_owned(d: &TypeDesc, slot: *mut u8) {
    // SAFETY: per the contract of each kind.
    unsafe {
        match d.kind {
            KIND_INT | KIND_FLOAT | KIND_BOOL | KIND_POD => {}
            KIND_STRING => string::release(&*(slot as *const StrVal)),
            KIND_SHARED => obj::release(*(slot as *mut *mut Obj)),
            KIND_BYTES => {
                let v = &mut *(slot as *mut VecVal);
                if !v.ptr.is_null() {
                    alloc::free(v.ptr);
                    v.ptr = core::ptr::null_mut();
                }
            }
            KIND_LIST => crate::vec::drop_list(slot as *mut VecVal, &*d.inner0),
            KIND_MAP => map::drop_map(slot as *mut MapVal, &*d.inner0, d.inner1.as_ref()),
            KIND_SET => map::drop_map(slot as *mut MapVal, &*d.inner0, None),
            _ => {
                if let Some(f) = d.drop {
                    f(slot)
                }
            }
        }
    }
}

/// Duplicates the value in `src` into uninitialised `dst`.
///
/// # Safety
/// `src` holds a live value described by `d`; `dst` has room for `d.size` bytes.
#[inline(always)]
pub unsafe fn slot_copy(d: &TypeDesc, src: *const u8, dst: *mut u8) {
    // SAFETY: per the contract of each kind.
    unsafe {
        if d.kind <= KIND_BOOL && d.size == 8 {
            *(dst as *mut u64) = *(src as *const u64);
            return;
        }
        slot_copy_slow(d, src, dst)
    }
}

#[inline(never)]
unsafe fn slot_copy_slow(d: &TypeDesc, src: *const u8, dst: *mut u8) {
    // SAFETY: per the contract of each kind.
    unsafe {
        match d.kind {
            KIND_INT | KIND_FLOAT | KIND_BOOL | KIND_POD => {
                core::ptr::copy_nonoverlapping(src, dst, d.size as usize)
            }
            KIND_STRING => string::cloned(&*(src as *const StrVal)).write_to(dst as *mut StrVal),
            KIND_SHARED => {
                let p = *(src as *const *mut Obj);
                obj::retain(p);
                *(dst as *mut *mut Obj) = p;
            }
            KIND_BYTES => crate::vec::copy_bytes(src as *const VecVal, dst as *mut VecVal),
            KIND_LIST => {
                crate::vec::copy_list(src as *const VecVal, &*d.inner0, dst as *mut VecVal)
            }
            KIND_MAP => map::copy_map(
                src as *const MapVal,
                &*d.inner0,
                d.inner1.as_ref(),
                dst as *mut MapVal,
            ),
            KIND_SET => map::copy_map(src as *const MapVal, &*d.inner0, None, dst as *mut MapVal),
            _ => match d.copy {
                Some(f) => f(src, dst),
                None => core::ptr::copy_nonoverlapping(src, dst, d.size as usize),
            },
        }
    }
}

struct EqState {
    pairs: Vec<(usize, usize)>,
}
static EQ: Global<EqState> = Global::new(EqState { pairs: Vec::new() });
const MAX_EQ_DEPTH: usize = 200_000;

/// Registers a pair of objects being compared; 0 means the pair is already in progress
/// (the comparison assumes equal).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_eq_enter(a: *const u8, b: *const u8) -> u8 {
    // SAFETY: single threaded access.
    unsafe {
        let st = &mut *EQ.ptr();
        let key = (a as usize, b as usize);
        if st.pairs.as_slice().contains(&key) {
            return 0;
        }
        if st.pairs.len() >= MAX_EQ_DEPTH {
            fault::fault(b"equality comparison is nested too deeply");
        }
        st.pairs.push(key);
        1
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_eq_leave(_a: *const u8, _b: *const u8) {
    // SAFETY: single threaded access.
    unsafe {
        let st = &mut *EQ.ptr();
        st.pairs.pop();
    }
}

/// Exchanges the pairs registered by `msrt_eq_enter` with `other` (task switches).
pub(crate) fn swap_eq_pairs(other: &mut Vec<(usize, usize)>) {
    // SAFETY: single threaded access.
    unsafe { core::mem::swap(&mut (*EQ.ptr()).pairs, other) }
}

/// Number of object pairs currently registered by `msrt_eq_enter`.
pub fn eq_len() -> usize {
    // SAFETY: single threaded access.
    unsafe { (*EQ.ptr()).pairs.len() }
}

/// Drops pairs registered after the stack was `len` long (a fault left them behind).
pub fn eq_truncate(len: usize) {
    // SAFETY: single threaded access.
    unsafe {
        let st = &mut *EQ.ptr();
        while st.pairs.len() > len {
            st.pairs.pop();
        }
    }
}

/// Equality of two slots.
///
/// # Safety
/// Both slots hold live values described by `d`.
pub unsafe fn slot_eq(d: &TypeDesc, a: *const u8, b: *const u8) -> bool {
    // SAFETY: per the contract of each kind.
    unsafe {
        match d.kind {
            KIND_INT => *(a as *const i64) == *(b as *const i64),
            KIND_FLOAT => *(a as *const f64) == *(b as *const f64),
            KIND_BOOL => *a == *b,
            KIND_STRING => string::equal(a as *const StrVal, b as *const StrVal),
            KIND_BYTES => {
                let (x, y) = (&*(a as *const VecVal), &*(b as *const VecVal));
                x.len == y.len
                    && (x.len == 0
                        || core::slice::from_raw_parts(x.ptr, x.len)
                            == core::slice::from_raw_parts(y.ptr, y.len))
            }
            KIND_SHARED => match d.eq {
                Some(f) if *(a as *const usize) != *(b as *const usize) => {
                    let (p, q) = (*(a as *const *const u8), *(b as *const *const u8));
                    if p.is_null() || q.is_null() {
                        return false;
                    }
                    f(a, b) != 0
                }
                _ => *(a as *const usize) == *(b as *const usize),
            },
            KIND_POD => match d.eq {
                Some(f) => f(a, b) != 0,
                None => {
                    core::slice::from_raw_parts(a, d.size as usize)
                        == core::slice::from_raw_parts(b, d.size as usize)
                }
            },
            KIND_LIST => crate::vec::eq_list(a as *const VecVal, b as *const VecVal, &*d.inner0),
            KIND_MAP => map::eq_map(
                a as *const MapVal,
                b as *const MapVal,
                &*d.inner0,
                d.inner1.as_ref(),
            ),
            KIND_SET => map::eq_map(a as *const MapVal, b as *const MapVal, &*d.inner0, None),
            _ => match d.eq {
                Some(f) => f(a, b) != 0,
                None => {
                    core::slice::from_raw_parts(a, d.size as usize)
                        == core::slice::from_raw_parts(b, d.size as usize)
                }
            },
        }
    }
}

/// True when values of this type can be hashed.
pub fn hashable(d: &TypeDesc) -> bool {
    match d.kind {
        KIND_FLOAT | KIND_LIST | KIND_MAP | KIND_SET => false,
        KIND_SHARED | KIND_POD | KIND_CUSTOM => d.hash.is_some() || d.kind != KIND_CUSTOM,
        _ => true,
    }
}

/// Hash of a slot; equal values hash equally.
///
/// # Safety
/// The slot holds a live value described by `d`.
pub unsafe fn slot_hash(d: &TypeDesc, slot: *const u8) -> u64 {
    // SAFETY: per the contract of each kind.
    unsafe {
        match d.kind {
            KIND_INT => string::mix(*(slot as *const u64) ^ 0x9e37_79b9),
            KIND_BOOL => string::mix(*slot as u64 + 1),
            KIND_STRING => string::hash_bytes(string::bytes(slot as *const StrVal)),
            KIND_BYTES => {
                let v = &*(slot as *const VecVal);
                string::hash_bytes(if v.len == 0 {
                    &[]
                } else {
                    core::slice::from_raw_parts(v.ptr, v.len)
                })
            }
            KIND_SHARED => match d.hash {
                Some(f) if !(*(slot as *const *const u8)).is_null() => f(slot) as u64,
                _ => string::mix(*(slot as *const u64)),
            },
            KIND_POD | KIND_CUSTOM => match d.hash {
                Some(f) => f(slot) as u64,
                None if d.kind == KIND_POD => {
                    string::hash_bytes(core::slice::from_raw_parts(slot, d.size as usize))
                }
                None => fault::fault(b"runtime invariant: type is not hashable"),
            },
            _ => fault::fault(b"runtime invariant: type is not hashable"),
        }
    }
}

// ---- exported generic helpers ----

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_slot_drop(d: *const TypeDesc, slot: *mut u8) {
    // SAFETY: caller contract.
    unsafe { slot_drop(&*d, slot) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_slot_copy(d: *const TypeDesc, src: *const u8, dst: *mut u8) {
    // SAFETY: caller contract.
    unsafe { slot_copy(&*d, src, dst) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_slot_eq(d: *const TypeDesc, a: *const u8, b: *const u8) -> u8 {
    // SAFETY: caller contract.
    unsafe { slot_eq(&*d, a, b) as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_slot_hash(d: *const TypeDesc, slot: *const u8) -> i64 {
    // SAFETY: caller contract.
    unsafe { slot_hash(&*d, slot) as i64 }
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_hash_int(v: i64) -> i64 {
    string::mix(v as u64 ^ 0x9e37_79b9) as i64
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_hash_bytes(p: *const u8, len: usize) -> i64 {
    // SAFETY: caller passes a readable range.
    unsafe { string::hash_bytes(core::slice::from_raw_parts(p, len)) as i64 }
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_hash_combine(a: i64, b: i64) -> i64 {
    string::mix((a as u64).rotate_left(5) ^ b as u64) as i64
}
