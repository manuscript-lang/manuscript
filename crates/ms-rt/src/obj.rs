//! Object headers, reference counting and the allocator entry points.
use crate::alloc;
use core::ptr::null_mut;
use ms_rt_abi::Obj;

/// Allocates an object of `size` bytes with `rc = 1` and the given drop entry.
///
/// # Safety
/// `size` must be at least the header size; the caller initialises the rest.
#[inline]
pub unsafe fn new_obj(size: usize, drop: ms_rt_abi::DropFn) -> *mut Obj {
    let o = alloc::alloc(size) as *mut Obj;
    // SAFETY: freshly allocated block of at least 16 bytes.
    unsafe {
        (*o).rc = 1;
        (*o).drop = Some(drop);
    }
    o
}

/// Adds a reference. Null is ignored.
///
/// # Safety
/// `o` must be null or a live object.
#[inline(always)]
pub unsafe fn retain(o: *mut Obj) {
    if !o.is_null() {
        // SAFETY: live object per the contract.
        unsafe { (*o).rc += 1 };
    }
}

/// Drops a reference, destroying the object at zero. Null is ignored.
///
/// # Safety
/// `o` must be null or a live object the caller owns a reference to.
#[inline(always)]
pub unsafe fn release(o: *mut Obj) {
    if !o.is_null() {
        debug_assert!(
            !alloc::arena_released(),
            "runtime object released after its isolate's arena ended (a thread-local holds it?)"
        );
        // SAFETY: live object per the contract.
        unsafe {
            (*o).rc -= 1;
            if (*o).rc == 0 {
                drop_slow(o);
            }
        }
    }
}

const MAX_DROP_DEPTH: usize = 4096;
crate::isolate_static! {
    static DROP_DEPTH: usize = 0;
}
crate::isolate_static! {
    static PENDING: *mut Obj = null_mut();
}
/// Runs an object's drop entry, deferring when the drop nesting is deep so long
/// chains (linked lists, deep trees) cannot overflow the stack.
///
/// # Safety
/// `o` must be an object whose count just reached zero.
#[inline(never)]
pub unsafe fn drop_slow(o: *mut Obj) {
    // SAFETY: single threaded access to the drop state; `o` is dead and owned by us.
    unsafe {
        let depth = DROP_DEPTH.ptr();
        if *depth >= MAX_DROP_DEPTH {
            (*o).rc = *PENDING.ptr() as usize;
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
                *PENDING.ptr() = (*p).rc as *mut Obj;
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
pub unsafe extern "C-unwind" fn msrt_alloc(size: usize) -> *mut u8 {
    alloc::alloc(size)
}

#[unsafe(no_mangle)]
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

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_retain(o: *mut Obj) {
    // SAFETY: forwarded contract.
    unsafe { retain(o) }
}

/// Returns a second owned reference to the same object: the clone of a shared native handle.
///
/// # Safety
/// `o` must be a live object.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_obj_share(o: *const Obj) -> *mut Obj {
    let o = o.cast_mut();
    // SAFETY: forwarded contract; the retain makes the returned reference an owner.
    unsafe { retain(o) };
    o
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_release(o: *mut Obj) {
    // SAFETY: forwarded contract.
    unsafe { release(o) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_drop_slow(o: *mut Obj) {
    // SAFETY: forwarded contract.
    unsafe { drop_slow(o) }
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

    #[test]
    fn retain_release_drops_once() {
        let _g = lock();
        // SAFETY: objects created and released per the contract.
        unsafe {
            *DROPS.ptr() = 0;
            let o = new_obj(16, count_drop);
            retain(o);
            release(o);
            assert_eq!(*DROPS.ptr(), 0);
            release(o);
            assert_eq!(*DROPS.ptr(), 1);
            release(null_mut());
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
            release((*n).next);
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
                let n = new_obj(size_of::<Node>(), drop_node) as *mut Node;
                (*n).next = head;
                head = n as *mut Obj;
            }
            release(head);
            assert_eq!(*FREED.ptr(), 2_000_000);
        }
    }
}
