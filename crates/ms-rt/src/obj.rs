//! Object headers, their clone and drop entries, and the allocator entry points.
use crate::alloc;
use core::ptr::null_mut;
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
    if o.is_null() {
        return o;
    }
    // SAFETY: live object per the contract.
    unsafe {
        match (*o).clone {
            Some(clone) => clone(o),
            None => crate::fault::fatal(b"copy of a value that has one owner"),
        }
    }
}

/// Drops an object its owner is done with, destroying it. Null is ignored.
///
/// # Safety
/// `o` must be null or a live object the caller owns.
#[inline(always)]
pub unsafe fn drop_obj(o: *mut Obj) {
    if !o.is_null() {
        // SAFETY: live object per the contract.
        unsafe { drop_slow(o) }
    }
}

const MAX_DROP_DEPTH: usize = 4096;
crate::isolate_static! {
    static DROP_DEPTH: usize = 0;
}
crate::isolate_static! {
    static PENDING: *mut Obj = null_mut();
}

/// The next object in the pending list, linked through the dead object's clone slot.
unsafe fn pending_next(o: *mut Obj) -> *mut Obj {
    // SAFETY: `o` is a dead object whose clone slot holds a pending link.
    unsafe { (*o).clone.map_or(null_mut(), |f| f as *mut Obj) }
}

/// Runs an object's drop entry, deferring when the drop nesting is deep so long
/// chains (linked lists, deep trees) cannot overflow the stack.
///
/// # Safety
/// `o` must be an object its owner just dropped.
#[inline(never)]
pub unsafe fn drop_slow(o: *mut Obj) {
    // SAFETY: single threaded access to the drop state; `o` is dead and owned by us.
    unsafe {
        let depth = DROP_DEPTH.ptr();
        if *depth >= MAX_DROP_DEPTH {
            // The dead object's clone slot links the pending list.
            let next = *PENDING.ptr();
            (*o).clone = if next.is_null() {
                None
            } else {
                Some(core::mem::transmute::<*mut Obj, CloneFn>(next))
            };
            *PENDING.ptr() = o;
            return;
        }
        *depth += 1;
        let drop = (*o)
            .drop
            .unwrap_or_else(|| crate::fault::fatal(b"object without drop"));
        drop(o);
        *depth -= 1;
        if *depth == 0 {
            while !(*PENDING.ptr()).is_null() {
                let p = *PENDING.ptr();
                *PENDING.ptr() = pending_next(p);
                *depth = 1;
                let drop = (*p)
                    .drop
                    .unwrap_or_else(|| crate::fault::fatal(b"object without drop"));
                drop(p);
                *depth = 0;
            }
        }
    }
}

/// Writes small-block heap bytes (`used`, `in_use`) to `out[0..2]`, for `@std/process` `memory_usage`.
///
/// # Safety
/// `out` must point to two writable `i64`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_heap_stats(out: *mut i64) {
    let [used, in_use] = crate::alloc::heap_stats();
    // SAFETY: the caller passes two writable words.
    unsafe {
        out.write(used);
        out.add(1).write(in_use);
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_alloc(size: usize) -> *mut u8 {
    alloc::alloc(size)
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_alloc_zeroed(size: usize) -> *mut u8 {
    alloc::alloc_zeroed(size)
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_realloc(p: *mut u8, size: usize) -> *mut u8 {
    // SAFETY: forwarded contract.
    unsafe { alloc::realloc(p, size) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_free(p: *mut u8) {
    // SAFETY: forwarded contract.
    unsafe { alloc::free(p) }
}

/// An independent copy of `o` through its clone entry (null stays null).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_obj_clone(o: *mut Obj) -> *mut Obj {
    // SAFETY: forwarded contract.
    unsafe { clone_obj(o) }
}

/// Drops the object `o` its owner is done with (null is ignored).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_obj_drop(o: *mut Obj) {
    // SAFETY: forwarded contract.
    unsafe { drop_obj(o) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::global::Process;
    use crate::testutil::lock;

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
