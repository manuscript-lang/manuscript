//! Type descriptors: drop, copy, equality and hash of values stored in slots.
use crate::fault;
use ms_rt_abi::*;

// Defined in C (runtime/core); declared here for the Rust code that still calls them.
unsafe extern "C-unwind" {
    pub safe static msrt_desc_int: TypeDesc;
    pub safe static msrt_desc_float: TypeDesc;
    pub safe static msrt_desc_float32: TypeDesc;
    pub safe static msrt_desc_bool: TypeDesc;
    pub safe static msrt_desc_string: TypeDesc;
    pub safe static msrt_desc_bytes: TypeDesc;
    pub fn msrt_slot_drop(d: *const TypeDesc, slot: *mut u8);
    pub fn msrt_slot_copy(d: *const TypeDesc, src: *const u8, dst: *mut u8);
    pub fn msrt_slot_eq(d: *const TypeDesc, a: *const u8, b: *const u8) -> u8;
    pub fn msrt_slot_hash(d: *const TypeDesc, slot: *const u8) -> i64;
    pub safe fn msrt_hash_combine(a: i64, b: i64) -> i64;
}

/// Drops the value in `slot`.
///
/// # Safety
/// `slot` holds a live value described by `d`.
#[inline]
pub(crate) unsafe fn slot_drop(d: &TypeDesc, slot: *mut u8) {
    // SAFETY: caller contract; `msrt_slot_drop` is defined in C.
    unsafe { msrt_slot_drop(d, slot) }
}

struct EqState {
    pairs: Vec<(usize, usize)>,
}
crate::isolate_static! {
    static EQ: EqState = EqState { pairs: Vec::new() };
}
const MAX_EQ_DEPTH: usize = 200_000;

/// Registers a pair of objects being compared; 0 means the pair is already in progress
/// (the comparison assumes equal).
#[unsafe(no_mangle)]
// ms: leaf
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
// ms: leaf
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
pub(crate) fn eq_len() -> usize {
    // SAFETY: single threaded access.
    unsafe { (*EQ.ptr()).pairs.len() }
}

/// Drops pairs registered after the stack was `len` long (a fault left them behind).
#[cfg(not(test))]
pub(crate) fn eq_truncate(len: usize) {
    // SAFETY: single threaded access.
    unsafe {
        let st = &mut *EQ.ptr();
        while st.pairs.len() > len {
            st.pairs.pop();
        }
    }
}
