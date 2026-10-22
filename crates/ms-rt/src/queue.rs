//! `PriorityQueue[T]`: a stable binary heap held in a refcounted object. `Queue[T]` is a
//! Manuscript record in `stdlib/collections.ms`.
use crate::alloc;
use crate::desc::{slot_copy, slot_drop};
use crate::fault;
use crate::obj;
use core::ptr::null_mut;
use ms_rt_abi::{Closure, Obj, TypeDesc};

// ---------------------------------------------------------------------------
// PriorityQueue
// ---------------------------------------------------------------------------

/// A stable binary heap: ties between equal priorities dequeue in enqueue order.
#[repr(C)]
pub struct PriorityQueueObj {
    hdr: Obj,
    desc: *const TypeDesc,
    /// Comparator closure whose code is `extern "C" fn(closure, a, b) -> i64` over element slots.
    compare: *mut Closure,
    capacity: usize,
    next: u64,
    buf: *mut u8,
    seqs: *mut u64,
    len: usize,
    cap: usize,
}

type CompareFn = unsafe extern "C" fn(*mut Closure, *const u8, *const u8) -> i64;

impl PriorityQueueObj {
    fn size(&self) -> usize {
        // SAFETY: the descriptor outlives every queue made from it.
        unsafe { (*self.desc).size as usize }
    }

    unsafe fn slot(&self, i: usize) -> *mut u8 {
        // SAFETY: callers keep `i` within the allocated buffer.
        unsafe { self.buf.add(i * self.size()) }
    }

    /// Whether the value at `a` (sequence `a_seq`) comes before the one at `b`.
    unsafe fn before(&self, a: *const u8, a_seq: u64, b: *const u8, b_seq: u64) -> bool {
        // SAFETY: the closure was built by the compiler for this element type.
        unsafe {
            let code: CompareFn = core::mem::transmute((*self.compare).code);
            let order = code(self.compare, a, b);
            order < 0 || (order == 0 && a_seq < b_seq)
        }
    }

    /// Moves entry `from` to `to` (the buffers do not overlap beyond one slot).
    unsafe fn move_entry(&mut self, from: usize, to: usize) {
        // SAFETY: both indices are within the buffers.
        unsafe {
            core::ptr::copy_nonoverlapping(self.slot(from), self.slot(to), self.size());
            *self.seqs.add(to) = *self.seqs.add(from);
        }
    }
}

unsafe extern "C" fn drop_priority_queue(o: *mut Obj) {
    // SAFETY: `o` is a priority queue whose count reached zero.
    unsafe {
        let q = &mut *(o as *mut PriorityQueueObj);
        for i in 0..q.len {
            slot_drop(&*q.desc, q.slot(i));
        }
        if !q.buf.is_null() {
            alloc::free(q.buf);
            alloc::free(q.seqs as *mut u8);
        }
        obj::release(q.compare as *mut Obj);
        alloc::free(o as *mut u8);
    }
}

/// A priority queue ordered by `compare` (retained). A present capacity must be positive.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_priority_queue_new(
    d: *const TypeDesc,
    compare: *mut Closure,
    has_capacity: u8,
    capacity: i64,
) -> *mut PriorityQueueObj {
    if has_capacity != 0 && capacity <= 0 {
        fault::fault_fmt(format_args!(
            "PriorityQueue: capacity must be between 1 and {}, found {capacity}",
            i64::MAX
        ));
    }
    // SAFETY: the block is large enough for a `PriorityQueueObj`, fully initialised here.
    unsafe {
        let q = obj::new_obj(
            core::mem::size_of::<PriorityQueueObj>(),
            drop_priority_queue,
        ) as *mut PriorityQueueObj;
        core::ptr::addr_of_mut!((*q).desc).write(d);
        obj::retain(compare as *mut Obj);
        core::ptr::addr_of_mut!((*q).compare).write(compare);
        core::ptr::addr_of_mut!((*q).capacity).write(if has_capacity != 0 {
            capacity as usize
        } else {
            0
        });
        core::ptr::addr_of_mut!((*q).next).write(0);
        core::ptr::addr_of_mut!((*q).buf).write(null_mut());
        core::ptr::addr_of_mut!((*q).seqs).write(null_mut());
        core::ptr::addr_of_mut!((*q).len).write(0);
        core::ptr::addr_of_mut!((*q).cap).write(0);
        q
    }
}

/// Adds `value` (a slot the queue takes over when it fits); a full queue drops it and answers 0.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_priority_queue_enqueue(
    q: *mut PriorityQueueObj,
    value: *mut u8,
) -> u8 {
    // SAFETY: `q` is a live queue and `value` a live slot of its element type.
    unsafe {
        let q = &mut *q;
        if q.capacity > 0 && q.len >= q.capacity {
            slot_drop(&*q.desc, value);
            return 0;
        }
        let seq = q.next;
        // Find the position first so a comparator fault leaves the heap intact.
        let mut at = q.len;
        while at > 0 {
            let parent = (at - 1) / 2;
            if !q.before(value, seq, q.slot(parent), *q.seqs.add(parent)) {
                break;
            }
            at = parent;
        }
        if q.len == q.cap {
            let cap = if q.cap == 0 { 4 } else { q.cap * 2 };
            let bytes = cap
                .checked_mul(q.size().max(1))
                .unwrap_or_else(|| fault::fault(b"queue size overflow"));
            if q.buf.is_null() {
                q.buf = alloc::alloc(bytes);
                q.seqs = alloc::alloc(cap * 8) as *mut u64;
            } else {
                q.buf = alloc::realloc(q.buf, bytes);
                q.seqs = alloc::realloc(q.seqs as *mut u8, cap * 8) as *mut u64;
            }
            q.cap = cap;
        }
        let mut i = q.len;
        while i > at {
            let parent = (i - 1) / 2;
            q.move_entry(parent, i);
            i = parent;
        }
        core::ptr::copy_nonoverlapping(value, q.slot(at), q.size());
        *q.seqs.add(at) = seq;
        q.len += 1;
        q.next += 1;
        1
    }
}

/// Moves the next value by priority into `out`; 0 when empty.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_priority_queue_dequeue(
    q: *mut PriorityQueueObj,
    out: *mut u8,
) -> u8 {
    // SAFETY: `q` is a live queue and `out` a writable slot of its element type.
    unsafe {
        let q = &mut *q;
        if q.len == 0 {
            return 0;
        }
        core::ptr::copy_nonoverlapping(q.slot(0), out, q.size());
        let last = q.len - 1;
        // The last entry stays in place while the hole sinks; only slots below it are written.
        let entry = q.slot(last);
        let entry_seq = *q.seqs.add(last);
        let mut at = 0;
        loop {
            let mut child = at * 2 + 1;
            if child >= last {
                break;
            }
            if child + 1 < last
                && q.before(
                    q.slot(child + 1),
                    *q.seqs.add(child + 1),
                    q.slot(child),
                    *q.seqs.add(child),
                )
            {
                child += 1;
            }
            if !q.before(q.slot(child), *q.seqs.add(child), entry, entry_seq) {
                break;
            }
            q.move_entry(child, at);
            at = child;
        }
        if last > 0 && at != last {
            core::ptr::copy_nonoverlapping(entry, q.slot(at), q.size());
            *q.seqs.add(at) = entry_seq;
        }
        q.len = last;
        1
    }
}

/// Copies the next value by priority into `out`; 0 when empty.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_priority_queue_peek(
    q: *const PriorityQueueObj,
    out: *mut u8,
) -> u8 {
    // SAFETY: `q` is a live queue and `out` a writable slot of its element type.
    unsafe {
        let q = &*q;
        if q.len == 0 {
            return 0;
        }
        slot_copy(&*q.desc, q.slot(0), out);
        1
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_priority_queue_length(q: *const PriorityQueueObj) -> i64 {
    // SAFETY: `q` is a live queue.
    unsafe { (*q).len as i64 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_priority_queue_is_empty(q: *const PriorityQueueObj) -> u8 {
    // SAFETY: `q` is a live queue.
    unsafe { ((*q).len == 0) as u8 }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::msrt_desc_int;
    use crate::testutil;

    #[repr(C)]
    struct TestClosure {
        hdr: Obj,
        code: *const u8,
    }

    unsafe extern "C" fn int_order(_: *mut Closure, a: *const u8, b: *const u8) -> i64 {
        // SAFETY: int slots.
        unsafe { (*(a as *const i64) / 10).cmp(&(*(b as *const i64) / 10)) as i64 }
    }

    unsafe extern "C" fn nothing(_: *mut Obj) {}

    #[test]
    fn priority_queue_is_stable() {
        let _g = testutil::lock();
        // SAFETY: int slots throughout; the closure is a static-lifetime test object.
        unsafe {
            let closure =
                obj::new_obj(core::mem::size_of::<TestClosure>(), nothing) as *mut TestClosure;
            (*closure).code = int_order as *const u8;
            let q = msrt_priority_queue_new(&msrt_desc_int, closure as *mut Closure, 0, 0);
            // Priorities are tens; equal tens keep enqueue order.
            for mut v in [31i64, 12, 35, 11, 20, 33, 10] {
                assert_eq!(
                    msrt_priority_queue_enqueue(q, &mut v as *mut i64 as *mut u8),
                    1
                );
            }
            let mut out = 0i64;
            let mut order = Vec::new();
            while msrt_priority_queue_dequeue(q, &mut out as *mut i64 as *mut u8) == 1 {
                order.push(out);
            }
            assert_eq!(order, [12, 11, 10, 20, 31, 35, 33]);
            obj::release(q as *mut Obj);
            obj::release(closure as *mut Obj);
        }
    }
}
