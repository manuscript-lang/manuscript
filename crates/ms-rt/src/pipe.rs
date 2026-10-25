//! In-memory duplex message pipes between isolates, for the worker channels of `@std/workers.ms`.
//!
//! A pipe has two ends; a message sent on one end is read from the other, in order. Messages
//! are byte strings (the channel layer in Manuscript encodes values as JSON). Everything the
//! pipe holds, including the messages, lives in system memory, because the isolates on its two
//! ends have arenas of their own that end with the isolate. A task that must wait (no message
//! to read, or no room to send) parks on a remote token of its isolate, recorded on the lane;
//! the other end posts it.
use crate::task::{TOKEN_PEER, TOKEN_REMOTE, msrt_token_new, msrt_token_post_remote};
use core::ptr::null_mut;
use ms_rt_abi::StrVal;
use std::sync::Mutex;

/// Messages one direction holds before a send waits.
const ROOM: usize = 16;
/// Pipes alive at once.
const MAX_PIPES: usize = 1024;

/// `send` / `receive` results.
const OK: i64 = 0;
/// This end, or the other, is closed (a send); this end is closed (a receive).
const CLOSED: i64 = 1;
/// The other end closed and every message was read.
const ENDED: i64 = 2;

struct Message {
    next: *mut Message,
    len: usize,
    // The bytes follow.
}

struct Waiter {
    next: *mut Waiter,
    token: u64,
}

/// One direction.
struct Lane {
    head: *mut Message,
    tail: *mut Message,
    len: usize,
    waiters: *mut Waiter,
    sender_closed: bool,
    receiver_closed: bool,
}

impl Lane {
    const NEW: Lane = Lane {
        head: null_mut(),
        tail: null_mut(),
        len: 0,
        waiters: null_mut(),
        sender_closed: false,
        receiver_closed: false,
    };

    /// Posts and frees every waiter; each looks again at what it waited for.
    fn wake(&mut self) {
        let mut w = self.waiters;
        self.waiters = null_mut();
        while !w.is_null() {
            // SAFETY: waiters are system blocks owned by the lane.
            unsafe {
                msrt_token_post_remote((*w).token, 0);
                let next = (*w).next;
                crate::sys::free(w.cast());
                w = next;
            }
        }
    }

    fn clear(&mut self) {
        let mut m = self.head;
        while !m.is_null() {
            // SAFETY: messages are system blocks owned by the lane.
            unsafe {
                let next = (*m).next;
                crate::sys::free(m.cast());
                m = next;
            }
        }
        self.head = null_mut();
        self.tail = null_mut();
        self.len = 0;
    }

    fn wait_on(&mut self, token: u64) {
        // SAFETY: a plain system block.
        unsafe {
            let w = crate::sys::malloc(core::mem::size_of::<Waiter>()).cast::<Waiter>();
            if w.is_null() {
                crate::fault::fatal(b"out of memory");
            }
            w.write(Waiter {
                next: self.waiters,
                token,
            });
            self.waiters = w;
        }
    }
}

struct Pipe {
    generation: u32,
    /// Lane `s` carries what end `s` sends.
    lanes: [Lane; 2],
    open_ends: u8,
}

struct Table {
    pipes: [*mut Pipe; MAX_PIPES],
    generations: [u32; MAX_PIPES],
}

// SAFETY: the table is only touched under its mutex.
unsafe impl Send for Table {}

static TABLE: Mutex<Table> = Mutex::new(Table {
    pipes: [null_mut(); MAX_PIPES],
    generations: [0; MAX_PIPES],
});

fn table() -> std::sync::MutexGuard<'static, Table> {
    TABLE.lock().unwrap_or_else(|e| e.into_inner())
}

/// End id: generation, slot plus one, side. Never 0.
fn end_id(generation: u32, slot: usize, side: usize) -> i64 {
    ((generation as i64) << 32) | (((slot + 1) as i64) << 1) | side as i64
}

/// Finds the pipe an end belongs to, with the end's side.
fn find(t: &mut Table, end: i64) -> Option<(&mut Pipe, usize)> {
    let low = (end & 0xffff_ffff) as usize;
    let slot = (low >> 1).checked_sub(1)?;
    let generation = (end >> 32) as u32;
    let p = *t.pipes.get(slot)?;
    if p.is_null() {
        return None;
    }
    // SAFETY: a live pipe is a system block owned by the table.
    let pipe = unsafe { &mut *p };
    (pipe.generation == generation).then_some((pipe, low & 1))
}

/// Makes a pipe and returns its first end; the other end is [`msrt_pipe_peer`] of it. Returns 0
/// when too many pipes are alive.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_new() -> i64 {
    let mut t = table();
    let Some(slot) = t.pipes.iter().position(|p| p.is_null()) else {
        return 0;
    };
    // SAFETY: a plain system block.
    let p = unsafe { crate::sys::malloc(core::mem::size_of::<Pipe>()).cast::<Pipe>() };
    if p.is_null() {
        crate::fault::fatal(b"out of memory");
    }
    t.generations[slot] = t.generations[slot].wrapping_add(1) & 0x7fff_ffff;
    let generation = t.generations[slot];
    // SAFETY: `p` is a fresh block of the right size.
    unsafe {
        p.write(Pipe {
            generation,
            lanes: [Lane::NEW, Lane::NEW],
            open_ends: 2,
        })
    };
    t.pipes[slot] = p;
    end_id(generation, slot, 0)
}

/// The other end of the pipe that `end` belongs to.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_peer(end: i64) -> i64 {
    end ^ 1
}

/// Waits for a token a lane will post, on the calling task.
fn park(token: u64) {
    crate::channel::msrt_channel_park(token as i64);
}

/// Sends `message` on `end`, waiting while the other end has many unread messages. Returns 0
/// sent, or 1 when this end or the other is closed.
///
/// # Safety
/// `message` points to a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_pipe_send(end: i64, message: *const StrVal) -> i64 {
    // SAFETY: a live string by contract.
    let bytes = unsafe { crate::string::bytes(&*message) };
    loop {
        let mut t = table();
        let Some((pipe, side)) = find(&mut t, end) else {
            return CLOSED;
        };
        let lane = &mut pipe.lanes[side];
        if lane.sender_closed || lane.receiver_closed {
            return CLOSED;
        }
        if lane.len < ROOM {
            // SAFETY: a system block of header plus bytes.
            unsafe {
                let m = crate::sys::malloc(core::mem::size_of::<Message>() + bytes.len())
                    .cast::<Message>();
                if m.is_null() {
                    crate::fault::fatal(b"out of memory");
                }
                m.write(Message {
                    next: null_mut(),
                    len: bytes.len(),
                });
                core::ptr::copy_nonoverlapping(
                    bytes.as_ptr(),
                    m.cast::<u8>().add(core::mem::size_of::<Message>()),
                    bytes.len(),
                );
                if lane.tail.is_null() {
                    lane.head = m;
                } else {
                    (*lane.tail).next = m;
                }
                lane.tail = m;
            }
            lane.len += 1;
            lane.wake();
            return OK;
        }
        // SAFETY: tokens belong to the calling isolate.
        let token = unsafe { msrt_token_new(TOKEN_REMOTE | TOKEN_PEER) };
        lane.wait_on(token);
        drop(t);
        park(token);
    }
}

/// Reads the next message on `end` into `*out`, waiting for one. Returns 0 read, 1 when this
/// end is closed, 2 when the other end closed and every message was read.
///
/// # Safety
/// `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_pipe_receive(end: i64, out: *mut StrVal) -> u8 {
    loop {
        let mut t = table();
        let Some((pipe, side)) = find(&mut t, end) else {
            return CLOSED as u8;
        };
        let lane = &mut pipe.lanes[1 - side];
        if lane.receiver_closed {
            return CLOSED as u8;
        }
        if !lane.head.is_null() {
            // SAFETY: the head is a system block the lane owns.
            unsafe {
                let m = lane.head;
                lane.head = (*m).next;
                if lane.head.is_null() {
                    lane.tail = null_mut();
                }
                lane.len -= 1;
                let data = core::slice::from_raw_parts(
                    m.cast::<u8>().add(core::mem::size_of::<Message>()),
                    (*m).len,
                );
                *out = crate::string::from_bytes(data);
                crate::sys::free(m.cast());
            }
            lane.wake();
            return OK as u8;
        }
        if lane.sender_closed {
            return ENDED as u8;
        }
        // SAFETY: tokens belong to the calling isolate.
        let token = unsafe { msrt_token_new(TOKEN_REMOTE | TOKEN_PEER) };
        lane.wait_on(token);
        drop(t);
        park(token);
    }
}

/// Closes `end`: the other end reads what is left, then sees the end; this end reads and sends
/// nothing more. Safe to call again.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_close(end: i64) {
    let mut t = table();
    let Some((pipe, side)) = find(&mut t, end) else {
        return;
    };
    let out = &mut pipe.lanes[side];
    if out.sender_closed && pipe.lanes[1 - side].receiver_closed {
        return;
    }
    pipe.lanes[side].sender_closed = true;
    pipe.lanes[side].wake();
    let incoming = &mut pipe.lanes[1 - side];
    incoming.receiver_closed = true;
    incoming.clear();
    incoming.wake();
    pipe.open_ends -= 1;
    if pipe.open_ends == 0 {
        let slot = ((end & 0xffff_ffff) as usize >> 1) - 1;
        let p = core::mem::replace(&mut t.pipes[slot], null_mut());
        // SAFETY: both ends are closed, so the lanes hold no message and no waiter.
        unsafe { crate::sys::free(p.cast()) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::string::{bytes, from_bytes};

    fn send(end: i64, text: &str) -> i64 {
        // SAFETY: a fresh string, released after the send.
        unsafe {
            let s = from_bytes(text.as_bytes());
            let r = msrt_pipe_send(end, &s);
            crate::string::release_opt(&s);
            r
        }
    }

    fn receive(end: i64) -> Result<String, i64> {
        let mut out = crate::string::NO_STR;
        // SAFETY: `out` is writable; its string is released after the copy.
        unsafe {
            let r = msrt_pipe_receive(end, &mut out);
            if r != 0 {
                return Err(r as i64);
            }
            let text = String::from_utf8_lossy(bytes(&out)).into_owned();
            crate::string::release_opt(&out);
            Ok(text)
        }
    }

    #[test]
    fn messages_arrive_in_order_in_both_directions() {
        let _g = crate::testutil::lock();
        let a = msrt_pipe_new();
        let b = msrt_pipe_peer(a);
        assert_eq!(send(a, "one"), OK);
        assert_eq!(send(a, "two"), OK);
        assert_eq!(send(b, "back"), OK);
        assert_eq!(receive(b), Ok("one".into()));
        assert_eq!(receive(b), Ok("two".into()));
        assert_eq!(receive(a), Ok("back".into()));
        msrt_pipe_close(a);
        msrt_pipe_close(b);
        crate::task::teardown();
    }

    #[test]
    fn a_closed_end_drains_then_ends_and_blocks_sends() {
        let _g = crate::testutil::lock();
        let a = msrt_pipe_new();
        let b = msrt_pipe_peer(a);
        assert_eq!(send(a, "last"), OK);
        msrt_pipe_close(a);
        msrt_pipe_close(a);
        assert_eq!(receive(b), Ok("last".into()));
        assert_eq!(receive(b), Err(ENDED));
        assert_eq!(send(b, "late"), CLOSED);
        assert_eq!(receive(a), Err(CLOSED));
        msrt_pipe_close(b);
        // The freed pipe's ends read as closed.
        assert_eq!(send(a, "x"), CLOSED);
        crate::task::teardown();
    }

    #[test]
    fn a_receive_waits_for_a_message_from_another_thread() {
        let _g = crate::testutil::lock();
        let a = msrt_pipe_new();
        let b = msrt_pipe_peer(a);
        // The sending thread plays a worker isolate, which the process counts from its spawn.
        crate::isolate::count_worker();
        let sender = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(20));
            // It has no scheduler state of its own to wait on, and the pipe has room.
            assert_eq!(send(a, "hi"), OK);
            crate::isolate::retire_worker();
        });
        assert_eq!(receive(b), Ok("hi".into()));
        sender.join().unwrap();
        msrt_pipe_close(a);
        msrt_pipe_close(b);
        crate::task::teardown();
    }
}
