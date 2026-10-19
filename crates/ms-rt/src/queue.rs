//! `Queue[T]`: a local mutable FIFO held in a refcounted object, so copies of a queue value
//! share one queue as they do in the Go runtime. Elements live in a growable buffer with a
//! head index; consumed slots are reclaimed by sliding the live range down once the head
//! passes half the buffer.
use crate::alloc;
use crate::desc::{slot_copy, slot_drop};
use crate::fault;
use crate::obj;
use core::ptr::null_mut;
use ms_rt_abi::{Obj, TypeDesc};

#[repr(C)]
pub struct QueueObj {
    hdr: Obj,
    desc: *const TypeDesc,
    /// Zero means unbounded.
    capacity: usize,
    buf: *mut u8,
    head: usize,
    len: usize,
    cap: usize,
}

impl QueueObj {
    fn size(&self) -> usize {
        // SAFETY: the descriptor outlives every queue made from it.
        unsafe { (*self.desc).size as usize }
    }

    unsafe fn slot(&self, i: usize) -> *mut u8 {
        // SAFETY: callers keep `i` within the allocated buffer.
        unsafe { self.buf.add(i * self.size()) }
    }

    fn live(&self) -> usize {
        self.len - self.head
    }
}

unsafe extern "C" fn drop_queue(o: *mut Obj) {
    // SAFETY: `o` is a queue whose count reached zero.
    unsafe {
        let q = &mut *(o as *mut QueueObj);
        for i in q.head..q.len {
            slot_drop(&*q.desc, q.slot(i));
        }
        if !q.buf.is_null() {
            alloc::free(q.buf);
        }
        alloc::free(o as *mut u8);
    }
}

/// A queue of elements described by `d`. A present capacity must be positive.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_queue_new(
    d: *const TypeDesc,
    has_capacity: u8,
    capacity: i64,
) -> *mut QueueObj {
    if has_capacity != 0 && capacity <= 0 {
        fault::fault_fmt(format_args!(
            "Queue: capacity must be between 1 and {}, found {capacity}",
            i64::MAX
        ));
    }
    // SAFETY: the block is large enough for a `QueueObj`, fully initialised here.
    unsafe {
        let q = obj::new_obj(core::mem::size_of::<QueueObj>(), drop_queue) as *mut QueueObj;
        core::ptr::addr_of_mut!((*q).desc).write(d);
        core::ptr::addr_of_mut!((*q).capacity).write(if has_capacity != 0 {
            capacity as usize
        } else {
            0
        });
        core::ptr::addr_of_mut!((*q).buf).write(null_mut());
        core::ptr::addr_of_mut!((*q).head).write(0);
        core::ptr::addr_of_mut!((*q).len).write(0);
        core::ptr::addr_of_mut!((*q).cap).write(0);
        q
    }
}

/// Appends `value` (a slot the queue takes over when it fits). A full bounded queue drops the
/// value and answers 0.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_queue_enqueue(q: *mut QueueObj, value: *mut u8) -> u8 {
    // SAFETY: `q` is a live queue and `value` a live slot of its element type.
    unsafe {
        let q = &mut *q;
        if q.capacity > 0 && q.live() >= q.capacity {
            slot_drop(&*q.desc, value);
            return 0;
        }
        if q.len == q.cap {
            if q.head > 0 && q.head * 2 >= q.len {
                // Slide the live range down instead of growing.
                let size = q.size();
                core::ptr::copy(q.slot(q.head), q.buf, q.live() * size);
                q.len -= q.head;
                q.head = 0;
            } else {
                let cap = if q.cap == 0 { 4 } else { q.cap * 2 };
                let bytes = cap
                    .checked_mul(q.size().max(1))
                    .unwrap_or_else(|| fault::fault(b"queue size overflow"));
                q.buf = if q.buf.is_null() {
                    alloc::alloc(bytes)
                } else {
                    alloc::realloc(q.buf, bytes)
                };
                q.cap = cap;
            }
        }
        core::ptr::copy_nonoverlapping(value, q.slot(q.len), q.size());
        q.len += 1;
        1
    }
}

/// Moves the oldest element into `out`; 0 when empty.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_queue_dequeue(q: *mut QueueObj, out: *mut u8) -> u8 {
    // SAFETY: `q` is a live queue and `out` a writable slot of its element type.
    unsafe {
        let q = &mut *q;
        if q.live() == 0 {
            return 0;
        }
        core::ptr::copy_nonoverlapping(q.slot(q.head), out, q.size());
        q.head += 1;
        if q.head == q.len {
            q.head = 0;
            q.len = 0;
        }
        1
    }
}

/// Copies the oldest element into `out`; 0 when empty.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_queue_peek(q: *const QueueObj, out: *mut u8) -> u8 {
    // SAFETY: `q` is a live queue and `out` a writable slot of its element type.
    unsafe {
        let q = &*q;
        if q.live() == 0 {
            return 0;
        }
        slot_copy(&*q.desc, q.slot(q.head), out);
        1
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_queue_length(q: *const QueueObj) -> i64 {
    // SAFETY: `q` is a live queue.
    unsafe { (*q).live() as i64 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_queue_is_empty(q: *const QueueObj) -> u8 {
    // SAFETY: `q` is a live queue.
    unsafe { ((*q).live() == 0) as u8 }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::{msrt_desc_int, msrt_desc_string};
    use crate::testutil;

    #[test]
    fn fifo_with_compaction() {
        let _g = testutil::lock();
        let mut model = std::collections::VecDeque::new();
        // SAFETY: int slots throughout.
        unsafe {
            let q = msrt_queue_new(&msrt_desc_int, 0, 0);
            let mut out = 0i64;
            assert_eq!(msrt_queue_dequeue(q, &mut out as *mut i64 as *mut u8), 0);
            let mut next = 0i64;
            for round in 0..200 {
                for _ in 0..(round % 7 + 1) {
                    let mut v = next;
                    assert_eq!(msrt_queue_enqueue(q, &mut v as *mut i64 as *mut u8), 1);
                    model.push_back(next);
                    next += 1;
                }
                for _ in 0..(round % 5 + 1) {
                    let got = msrt_queue_dequeue(q, &mut out as *mut i64 as *mut u8);
                    match model.pop_front() {
                        Some(want) => assert_eq!((got, out), (1, want)),
                        None => assert_eq!(got, 0),
                    }
                }
                assert_eq!(msrt_queue_length(q), model.len() as i64);
            }
            obj::release(q as *mut Obj);
        }
    }

    #[test]
    fn bounded_and_peek() {
        let _g = testutil::lock();
        // SAFETY: int slots throughout.
        unsafe {
            let q = msrt_queue_new(&msrt_desc_int, 1, 2);
            let mut v = 7i64;
            assert_eq!(msrt_queue_enqueue(q, &mut v as *mut i64 as *mut u8), 1);
            v = 8;
            assert_eq!(msrt_queue_enqueue(q, &mut v as *mut i64 as *mut u8), 1);
            v = 9;
            assert_eq!(msrt_queue_enqueue(q, &mut v as *mut i64 as *mut u8), 0);
            let mut out = 0i64;
            assert_eq!(msrt_queue_peek(q, &mut out as *mut i64 as *mut u8), 1);
            assert_eq!(out, 7);
            assert_eq!(msrt_queue_length(q), 2);
            assert_eq!(msrt_queue_dequeue(q, &mut out as *mut i64 as *mut u8), 1);
            assert_eq!(out, 7);
            assert_eq!(msrt_queue_dequeue(q, &mut out as *mut i64 as *mut u8), 1);
            assert_eq!(out, 8);
            assert_eq!(msrt_queue_is_empty(q), 1);
            obj::release(q as *mut Obj);
            let _ = &msrt_desc_string;
        }
    }
}
