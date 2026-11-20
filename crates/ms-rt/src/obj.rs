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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::global::Process;
    use crate::testutil::lock;
    use core::ptr::null_mut;

    static DROPS: Process<usize> = Process::new(0);

    unsafe extern "C" fn count_drop(o: *mut Obj) {
        // SAFETY: test object allocated by new_obj.
        unsafe {
            *DROPS.ptr() += 1;
            alloc::free(o.cast());
        }
    }

    unsafe extern "C" fn count_clone(o: *mut Obj) -> *mut Obj {
        // SAFETY: a fresh object of the same shape as `o`.
        unsafe { new_obj(16, (*o).clone, count_drop) }
    }

    #[test]
    fn clone_makes_a_second_object_and_each_drops_once() {
        let _g = lock();
        // SAFETY: objects created and dropped per the contract.
        unsafe {
            *DROPS.ptr() = 0;
            let o = new_obj(16, Some(count_clone), count_drop);
            let c = clone_obj(o);
            assert_ne!(c, o);
            drop_obj(o);
            assert_eq!(*DROPS.ptr(), 1);
            drop_obj(c);
            assert_eq!(*DROPS.ptr(), 2);
            drop_obj(null_mut());
            assert!(clone_obj(null_mut()).is_null());
        }
    }

    #[repr(C)]
    struct Node {
        hdr: Obj,
        next: *mut Obj,
    }
    static FREED: Process<usize> = Process::new(0);

    unsafe extern "C" fn drop_node(o: *mut Obj) {
        // SAFETY: test node allocated below.
        unsafe {
            let n = o as *mut Node;
            drop_obj((*n).next);
            *FREED.ptr() += 1;
            alloc::free(o.cast());
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "two million objects are too slow to interpret")]
    fn deep_chain_does_not_overflow() {
        let _g = lock();
        // SAFETY: nodes created and linked per the contract.
        unsafe {
            *FREED.ptr() = 0;
            let mut head: *mut Obj = null_mut();
            for _ in 0..2_000_000 {
                let n = new_obj(size_of::<Node>(), None, drop_node) as *mut Node;
                (*n).next = head;
                head = n as *mut Obj;
            }
            drop_obj(head);
            assert_eq!(*FREED.ptr(), 2_000_000);
        }
    }
}
