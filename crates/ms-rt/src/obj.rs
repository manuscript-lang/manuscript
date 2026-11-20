//! Object headers, their clone and drop entries, and the allocator entry points.
use crate::alloc;
use ms_rt_abi::{CloneFn, Obj};

/// Allocates an object of `size` bytes with the given clone and drop entries.
///
/// # Safety
/// `size` must be at least the header size; the caller initialises the rest.
#[inline]
pub unsafe fn new_obj(size: usize, clone: Option<CloneFn>, drop: ms_rt_abi::DropFn) -> *mut Obj {
    let o = alloc::alloc(size) as *mut Obj;
    // SAFETY: freshly allocated block of at least 16 bytes.
    unsafe {
        (*o).clone = clone;
        (*o).drop = Some(drop);
    }
    o
}

/// An independent copy of an object through its clone entry. Null stays null; a value with one
/// owner, which has no clone entry, is a fault: the checker rejects every copy a program
/// could write of one, so reaching it is a compiler bug.
///
/// # Safety
/// `o` must be null or a live object.
#[inline(always)]
pub unsafe fn clone_obj(o: *mut Obj) -> *mut Obj {
    // SAFETY: forwarded contract.
    unsafe { msrt_obj_clone(o) }
}

/// Drops an object its owner is done with, destroying it. Null is ignored.
///
/// # Safety
/// `o` must be null or a live object the caller owns.
#[inline(always)]
pub unsafe fn drop_obj(o: *mut Obj) {
    // SAFETY: forwarded contract.
    unsafe { msrt_obj_drop(o) }
}

// Defined in C (runtime/core/obj.c): clone, drop (deep chains stay off the stack) and the work counters.
unsafe extern "C-unwind" {
    pub fn msrt_obj_clone(o: *mut Obj) -> *mut Obj;
    pub fn msrt_obj_drop(o: *mut Obj);
    pub safe fn msrt_ops_add(n: i64);
    pub fn msrt_counts(out: *mut u64);
}

// The allocator symbols are defined in runtime/core/alloc.c; the runtime reaches them under their old names.
pub use crate::alloc::{msrt_alloc, msrt_alloc_zeroed, msrt_free, msrt_heap_stats, msrt_realloc};
