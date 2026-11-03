//! `Pipe[T]`: an in-memory stream of whole values, any number of writers and one reader.
//!
//! A pipe is one of the few objects two threads touch at once, so it synchronizes itself: all
//! pipes live in one table behind one lock, held only to move a pointer or a list entry. A value
//! is written as a block of the process heap and read by pointer, never copied deeper; a reader or
//! a flush is a promise in the table of the thread that made it, completed by event from whichever
//! thread wrote or read.
//!
//! * `write` never waits: it moves the value into the queue, or straight to a waiting reader.
//! * `read` answers a promise: ready now if a value is queued, `none` (no value) once every writer
//!   has closed and the queue is empty, otherwise pending until a write.
//! * `flush` answers a promise that finishes when no more than `capacity` values are queued, or
//!   the reader has gone.
//!
//! The pipe starts with one writer, the `Pipe` value itself; `msrt_pipe_close_writer` releases
//! it, like any other writer.
use crate::desc::slot_drop;
use crate::{alloc, promise};
use ms_rt_abi::TypeDesc;
use std::collections::VecDeque;
use std::sync::Mutex;

/// Status of `msrt_pipe_write`: the value was taken.
pub const WRITTEN: i64 = 0;
/// Status of `msrt_pipe_write`: the reader is gone, so the value was dropped.
pub const CLOSED: i64 = 1;

struct Item {
    ptr: usize,
    desc: usize,
}

struct Pipe {
    generation: u32,
    live: bool,
    queue: VecDeque<Item>,
    capacity: usize,
    writers: u32,
    reader_open: bool,
    /// The read promise waiting for a value: its id (the thread is in the id).
    reader: Option<i64>,
    /// Flush promises waiting for the queue to fall to `capacity`.
    flushes: Vec<i64>,
}

static PIPES: Mutex<Vec<Pipe>> = Mutex::new(Vec::new());

fn pipes() -> std::sync::MutexGuard<'static, Vec<Pipe>> {
    PIPES.lock().unwrap_or_else(|e| e.into_inner())
}

fn slot(table: &mut [Pipe], id: i64) -> Option<&mut Pipe> {
    let i = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    let p = table.get_mut(i)?;
    (p.live && i64::from(p.generation) == id >> 32).then_some(p)
}

fn free_block(item: &Item) {
    // SAFETY: the block holds an owned value of its descriptor that nobody took.
    unsafe {
        slot_drop(&*(item.desc as *const TypeDesc), item.ptr as *mut u8);
        alloc::free(item.ptr as *mut u8);
    }
}

/// Frees the pipe when its last writer and its reader are gone.
fn retire(p: &mut Pipe) {
    if p.writers == 0 && !p.reader_open {
        for item in p.queue.drain(..) {
            free_block(&item);
        }
        p.live = false;
        p.queue = VecDeque::new();
    }
}

/// Creates a pipe whose writers' `flush` waits above `capacity` queued values.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_new(capacity: i64) -> i64 {
    let mut table = pipes();
    let i = match table
        .iter()
        .position(|p| !p.live && p.generation < 0x7fff_ffff)
    {
        Some(i) => i,
        None => {
            table.push(Pipe {
                generation: 0,
                live: false,
                queue: VecDeque::new(),
                capacity: 0,
                writers: 0,
                reader_open: false,
                reader: None,
                flushes: Vec::new(),
            });
            table.len() - 1
        }
    };
    let p = &mut table[i];
    p.generation += 1;
    p.live = true;
    p.capacity = capacity.max(0) as usize;
    p.writers = 1;
    p.reader_open = true;
    p.reader = None;
    p.flushes.clear();
    (i64::from(p.generation) << 32) | (i as i64 + 1)
}

/// Another writing end, like `dup` on a descriptor.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_add_writer(pipe: i64) {
    if let Some(p) = slot(&mut pipes(), pipe) {
        p.writers += 1;
    }
}

/// Moves `value` into the pipe and answers `WRITTEN`, or `CLOSED` (the value is dropped) when the
/// reader is gone. It never waits.
///
/// # Safety
/// `value` holds an owned value of `d`, which the callee takes.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_pipe_write(
    pipe: i64,
    value: *mut u8,
    d: ms_rt_abi::ValueDesc,
) -> i64 {
    // SAFETY: forwarded contract.
    let ptr = unsafe {
        let size = (*d).size as usize;
        let block = alloc::alloc(size.max(1));
        core::ptr::copy_nonoverlapping(value, block, size);
        block as usize
    };
    let item = Item {
        ptr,
        desc: d as usize,
    };
    let reader = {
        let mut table = pipes();
        match slot(&mut table, pipe) {
            Some(p) if p.reader_open => match p.reader.take() {
                Some(reader) => Some(reader),
                None => {
                    p.queue.push_back(item);
                    return WRITTEN;
                }
            },
            _ => {
                drop(table);
                free_block(&item);
                return CLOSED;
            }
        }
    };
    if let Some(reader) = reader {
        promise::io_done_block(reader, item.ptr, item.desc, pipe);
    }
    WRITTEN
}

/// The read promise's cancel hook: the reader leaves the pipe's wait list.
fn reader_cancelled(id: i64, pipe: usize, _bits: u32) -> bool {
    if let Some(p) = slot(&mut pipes(), pipe as i64)
        && p.reader == Some(id)
    {
        p.reader = None;
    }
    false
}

/// Starts a read: answers a promise for the next value. It finishes with the value (take it with
/// `msrt_promise_take`), or with none once every writer has closed and the queue is empty. A pipe
/// has one reader, so a second read while one is pending faults.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_read(pipe: i64) -> i64 {
    let id = promise::io_new();
    enum Next {
        Value(Item),
        End,
        Wait,
    }
    let (next, released) = {
        let mut table = pipes();
        let Some(p) = slot(&mut table, pipe) else {
            drop(table);
            promise::io_done(id);
            return id;
        };
        if p.reader.is_some() {
            drop(table);
            crate::fault::fault(b"pipe: a read is already waiting");
        }
        let next = match p.queue.pop_front() {
            Some(item) => Next::Value(item),
            None if p.writers == 0 => Next::End,
            None => {
                p.reader = Some(id);
                Next::Wait
            }
        };
        (next, take_flushes(p))
    };
    complete_flushes(released);
    match next {
        Next::Value(item) => promise::io_done_block(id, item.ptr, item.desc, pipe),
        Next::End => promise::io_done(id),
        Next::Wait => promise::on_drop(id, reader_cancelled, pipe as usize),
    }
    id
}

/// The flushes that no longer wait, once the queue has fallen to its capacity.
fn take_flushes(p: &mut Pipe) -> Vec<i64> {
    if p.queue.len() <= p.capacity {
        core::mem::take(&mut p.flushes)
    } else {
        Vec::new()
    }
}

fn complete_flushes(ids: Vec<i64>) {
    for id in ids {
        promise::io_done_unit(id);
    }
}

/// Starts a flush: answers a promise that finishes when no more than `capacity` values are queued
/// or the reader is gone.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_flush(pipe: i64) -> i64 {
    let id = promise::io_new();
    let waits = {
        let mut table = pipes();
        match slot(&mut table, pipe) {
            Some(p) if p.reader_open && p.queue.len() > p.capacity => {
                p.flushes.push(id);
                true
            }
            _ => false,
        }
    };
    if waits {
        promise::on_drop(id, flush_cancelled, pipe as usize);
    } else {
        promise::io_done_unit(id);
    }
    id
}

/// The flush promise's cancel hook: it leaves the pipe's list.
fn flush_cancelled(id: i64, pipe: usize, _bits: u32) -> bool {
    if let Some(p) = slot(&mut pipes(), pipe as i64) {
        p.flushes.retain(|&f| f != id);
    }
    false
}

/// How many values are queued and not yet read.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_buffered(pipe: i64) -> i64 {
    slot(&mut pipes(), pipe).map_or(0, |p| p.queue.len() as i64)
}

/// Closes one writing end. When the last one closes, a waiting read finishes with none.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_close_writer(pipe: i64) {
    let reader = {
        let mut table = pipes();
        let Some(p) = slot(&mut table, pipe) else {
            return;
        };
        p.writers = p.writers.saturating_sub(1);
        let reader = if p.writers == 0 && p.queue.is_empty() {
            p.reader.take()
        } else {
            None
        };
        retire(p);
        reader
    };
    if let Some(reader) = reader {
        promise::io_done(reader);
    }
}

/// Closes the reading end: queued values are dropped, waiting flushes finish, and later writes
/// answer `CLOSED`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_close_reader(pipe: i64) {
    let flushes = {
        let mut table = pipes();
        let Some(p) = slot(&mut table, pipe) else {
            return;
        };
        p.reader_open = false;
        p.reader = None;
        for item in p.queue.drain(..) {
            free_block(&item);
        }
        let flushes = core::mem::take(&mut p.flushes);
        retire(p);
        flushes
    };
    complete_flushes(flushes);
}

/// Gives a value that was read but never taken (its promise was dropped first) back to the front
/// of the pipe, or drops it when the pipe has no reader.
pub(crate) fn unread(pipe: i64, ptr: usize, desc: usize) {
    let item = Item { ptr, desc };
    let mut table = pipes();
    match slot(&mut table, pipe) {
        Some(p) if p.reader_open => p.queue.push_front(item),
        _ => {
            drop(table);
            free_block(&item);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::msrt_desc_int;
    use crate::promise::{
        msrt_promise_drop, msrt_promise_put, msrt_promise_start, msrt_promise_take,
        msrt_promise_wait,
    };
    use crate::sched;
    use crate::testutil::lock;
    use ms_rt_abi::Closure;

    fn write_int(pipe: i64, mut v: i64) -> i64 {
        // SAFETY: `v` is an Int slot the call takes.
        unsafe { msrt_pipe_write(pipe, (&raw mut v).cast(), &msrt_desc_int) }
    }

    /// Waits for a read promise: the value, or `None` at the end.
    fn finish(read: i64) -> Option<i64> {
        assert_eq!(msrt_promise_wait(read, -1), promise::OK);
        let mut v = 0i64;
        // SAFETY: `v` is an Int slot.
        let some = unsafe { msrt_promise_take(read, &msrt_desc_int, (&raw mut v).cast()) } == 1;
        msrt_promise_drop(read);
        some.then_some(v)
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn values_come_out_whole_and_in_order_then_the_end() {
        let _g = lock();
        let pipe = msrt_pipe_new(4);
        for v in [1, 2, 3] {
            assert_eq!(write_int(pipe, v), WRITTEN);
        }
        assert_eq!(msrt_pipe_buffered(pipe), 3);
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(1));
        // A read that finds nothing waits for the write.
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(2));
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(3));
        let waiting = msrt_pipe_read(pipe);
        assert_eq!(promise::msrt_promise_done(waiting), 0);
        assert_eq!(write_int(pipe, 4), WRITTEN);
        assert_eq!(finish(waiting), Some(4));
        // The end: every writer closed and the queue empty.
        let end = msrt_pipe_read(pipe);
        msrt_pipe_close_writer(pipe);
        assert_eq!(finish(end), None);
        assert_eq!(finish(msrt_pipe_read(pipe)), None);
        msrt_pipe_close_reader(pipe);
        crate::task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_flush_waits_above_capacity_and_a_closed_reader_refuses_writes() {
        let _g = lock();
        let pipe = msrt_pipe_new(1);
        write_int(pipe, 1);
        let at_capacity = msrt_pipe_flush(pipe);
        assert_eq!(finish_unit(at_capacity), promise::OK);
        write_int(pipe, 2);
        write_int(pipe, 3);
        let waiting = msrt_pipe_flush(pipe);
        assert_eq!(promise::msrt_promise_done(waiting), 0);
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(1));
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(2));
        assert_eq!(finish_unit(waiting), promise::OK);
        msrt_pipe_close_reader(pipe);
        assert_eq!(write_int(pipe, 9), CLOSED);
        msrt_pipe_close_writer(pipe);
        crate::task::teardown();
    }

    fn finish_unit(id: i64) -> i64 {
        let code = msrt_promise_wait(id, -1);
        msrt_promise_drop(id);
        code
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_dropped_read_leaves_the_queue_alone() {
        let _g = lock();
        let pipe = msrt_pipe_new(4);
        let read = msrt_pipe_read(pipe);
        msrt_promise_drop(read);
        // The next write queues the value instead of handing it to the dropped read.
        assert_eq!(write_int(pipe, 7), WRITTEN);
        assert_eq!(msrt_pipe_buffered(pipe), 1);
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(7));
        msrt_pipe_close_writer(pipe);
        msrt_pipe_close_reader(pipe);
        crate::task::teardown();
    }

    unsafe extern "C-unwind" fn writer(closure: *mut Closure) {
        // SAFETY: the closure carries its promise's id and the pipe after the header.
        unsafe {
            let data = closure.add(1).cast::<i64>();
            let (id, pipe) = (data.read(), data.add(1).read());
            for v in 0..50 {
                write_int(pipe, v);
                crate::task::msrt_task_yield();
            }
            msrt_pipe_close_writer(pipe);
            let mut done = 1i64;
            msrt_promise_put(id, (&raw mut done).cast(), &msrt_desc_int, 0);
        }
    }

    unsafe extern "C" fn drop_closure(obj: *mut ms_rt_abi::Obj) {
        // SAFETY: the test closure has no captures and owns this allocation.
        unsafe { crate::alloc::free(obj.cast()) };
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn writers_on_other_threads_feed_one_reader() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        let pipe = msrt_pipe_new(8);
        let writers: Vec<i64> = (0..3).map(|_| promise::msrt_promise_new()).collect();
        for &id in &writers {
            msrt_pipe_add_writer(pipe);
            // SAFETY: the promise keeps a reference to the closure until its task has ended.
            unsafe {
                let size = size_of::<Closure>() + 16;
                let closure = crate::obj::new_obj(size, drop_closure).cast::<Closure>();
                (*closure).code = writer as *const u8;
                let data = closure.add(1).cast::<i64>();
                data.write(id);
                data.add(1).write(pipe);
                msrt_promise_start(id, closure);
                crate::obj::release(closure.cast());
            }
        }
        // The Pipe value's own writer goes: the three writers keep the pipe open.
        msrt_pipe_close_writer(pipe);
        let mut seen = vec![0usize; 50];
        let mut count = 0;
        while let Some(v) = finish(msrt_pipe_read(pipe)) {
            seen[v as usize] += 1;
            count += 1;
        }
        assert_eq!(count, 150);
        assert!(seen.iter().all(|&n| n == 3));
        for id in writers {
            msrt_promise_drop(id);
        }
        msrt_pipe_close_reader(pipe);
        sched::shutdown();
        crate::task::teardown();
    }
}
