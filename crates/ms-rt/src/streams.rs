//! The native stream table: one entry per descriptor-backed `ReadStream[Bytes]` or
//! `WriteStream[Bytes]`, in a flat array indexed by a generation-tagged id.
//!
//! * `read` answers a promise holding one chunk of `Bytes`, or no value at the end of the stream.
//!   It tries the system call at once and registers with the poller only when the call would block.
//! * `write` never waits: it appends to the entry's buffer. `flush` answers a promise that
//!   finishes when the buffer has drained.
//! * A failure ends the promise with no value and is kept on the entry; `msrt_streams_error`
//!   reads it, so the Manuscript side builds the `Error`.
use crate::vec::bytes_from;
use ms_rt_abi::VecVal;
use crate::{alloc, promise, sys, task};
use std::sync::Mutex;

/// `msrt_streams_open` flag: the entry reads.
pub const READS: i64 = 1;
/// `msrt_streams_open` flag: the entry writes.
pub const WRITES: i64 = 2;
/// `msrt_streams_open` flag: closing the entry closes the descriptor.
pub const OWNS: i64 = 4;
/// `msrt_streams_open` flag: put the descriptor in non-blocking mode (only for descriptors nothing else shares).
pub const NONBLOCK: i64 = 8;

/// Bytes a read asks the system for.
const CHUNK: usize = 64 * 1024;
/// Buffered bytes past which `write` drains on its own.
const AUTO_DRAIN: usize = 64 * 1024;

struct Entry {
    generation: u32,
    live: bool,
    fd: i32,
    flags: i64,
    /// Bytes accepted by `write` and not yet drained, and where the undrained part starts.
    out: Vec<u8>,
    out_start: usize,
    /// The read promise waiting on the poller, if any.
    reading: Option<i64>,
    /// The message of the failure that ended the last operation.
    error: Vec<u8>,
    /// Flush promises waiting for the buffer to drain.
    flushes: Vec<i64>,
}

static STREAMS: Mutex<Vec<Entry>> = Mutex::new(Vec::new());

fn streams() -> std::sync::MutexGuard<'static, Vec<Entry>> {
    STREAMS.lock().unwrap_or_else(|e| e.into_inner())
}

fn slot(table: &mut [Entry], id: i64) -> Option<&mut Entry> {
    let i = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    let e = table.get_mut(i)?;
    (e.live && i64::from(e.generation) == id >> 32).then_some(e)
}

/// Adds a stream over `fd` and answers its id.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_streams_open(fd: i64, flags: i64) -> i64 {
    if flags & NONBLOCK != 0 {
        // SAFETY: plain fcntl calls on a descriptor the caller hands over.
        unsafe {
            let current = sys::fcntl(fd as i32, sys::F_GETFL);
            if current >= 0 {
                sys::fcntl(fd as i32, sys::F_SETFL, current | sys::O_NONBLOCK);
            }
        }
    }
    let mut table = streams();
    let i = match table
        .iter()
        .position(|e| !e.live && e.generation < 0x7fff_ffff)
    {
        Some(i) => i,
        None => {
            table.push(Entry {
                generation: 0,
                live: false,
                fd: -1,
                flags: 0,
                out: Vec::new(),
                out_start: 0,
                reading: None,
                error: Vec::new(),
                flushes: Vec::new(),
            });
            table.len() - 1
        }
    };
    let e = &mut table[i];
    e.generation += 1;
    e.live = true;
    e.fd = fd as i32;
    e.flags = flags;
    e.out.clear();
    e.out_start = 0;
    e.reading = None;
    e.error.clear();
    e.flushes.clear();
    (i64::from(e.generation) << 32) | (i as i64 + 1)
}

fn fail(e: &mut Entry, what: &str) {
    e.error = format!("{what}: os error {}", sys::last_errno()).into_bytes();
}

enum Step {
    Data(Vec<u8>),
    End,
    Blocked,
    Failed,
}

fn try_read(e: &mut Entry) -> Step {
    let mut buf = vec![0u8; CHUNK];
    loop {
        // SAFETY: `buf` is writable for CHUNK bytes.
        let n = unsafe { sys::read(e.fd, buf.as_mut_ptr().cast(), CHUNK) };
        if n > 0 {
            buf.truncate(n as usize);
            return Step::Data(buf);
        }
        if n == 0 {
            return Step::End;
        }
        match sys::last_errno() {
            sys::EINTR => continue,
            sys::EAGAIN => return Step::Blocked,
            _ => {
                fail(e, "read");
                return Step::Failed;
            }
        }
    }
}

fn finish_data(id: i64, data: &[u8]) {
    let block = alloc::alloc(core::mem::size_of::<VecVal>());
    // SAFETY: `block` is a fresh block for one `Bytes` value, which the promise then owns.
    unsafe { bytes_from(data, block.cast()) };
    promise::io_done_block(
        id,
        block as usize,
        &crate::desc::msrt_desc_bytes as *const _ as usize,
        0,
    );
}

/// The poller says the descriptor may be readable: try again.
fn read_retry(id: i64, stream: usize, bits: u32) -> bool {
    if bits & task::WAIT_CANCELLED != 0 {
        if let Some(e) = slot(&mut streams(), stream as i64) {
            e.reading = None;
        }
        return true;
    }
    let step = {
        let mut table = streams();
        let Some(e) = slot(&mut table, stream as i64) else {
            drop(table);
            promise::io_done(id);
            return true;
        };
        let step = try_read(e);
        if !matches!(step, Step::Blocked) {
            e.reading = None;
        }
        step
    };
    match step {
        Step::Data(data) => finish_data(id, &data),
        Step::End | Step::Failed => promise::io_done(id),
        Step::Blocked => return false,
    }
    true
}

/// A promise for the next chunk of `Bytes` (take it with `msrt_promise_take`), with no value at
/// the end of the stream or after a failure (`msrt_streams_error`). A second read while one is
/// pending faults.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_streams_read(stream: i64) -> i64 {
    let id = promise::io_new();
    let step = {
        let mut table = streams();
        let Some(e) = slot(&mut table, stream) else {
            drop(table);
            promise::io_done(id);
            return id;
        };
        if e.flags & READS == 0 {
            e.error = b"read: the stream is not readable".to_vec();
            drop(table);
            promise::io_done(id);
            return id;
        }
        if e.reading.is_some() {
            drop(table);
            crate::fault::fault(b"stream: a read is already waiting");
        }
        e.error.clear();
        let step = try_read(e);
        if matches!(step, Step::Blocked) {
            e.reading = Some(id);
        }
        step
    };
    match step {
        Step::Data(data) => finish_data(id, &data),
        Step::End | Step::Failed => promise::io_done(id),
        Step::Blocked => {
            let fd = fd_of(stream);
            if !promise::io_on_ready(id, fd, task::WAIT_READ, -1, read_retry, stream as usize) {
                if let Some(e) = slot(&mut streams(), stream) {
                    e.reading = None;
                }
                promise::io_done(id);
            }
        }
    }
    id
}

fn fd_of(stream: i64) -> i32 {
    slot(&mut streams(), stream).map_or(-1, |e| e.fd)
}

/// Appends `data` to the buffer; 0 taken, 1 the stream is closed or not writable. Never waits.
///
/// # Safety
/// `data` is a live `Bytes` value.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_streams_write(stream: i64, data: *const VecVal) -> i64 {
    // SAFETY: caller contract.
    let bytes = unsafe {
        let b = &*data;
        if b.len == 0 {
            &[][..]
        } else {
            core::slice::from_raw_parts(b.ptr, b.len)
        }
    };
    let mut table = streams();
    let Some(e) = slot(&mut table, stream) else {
        return 1;
    };
    if e.flags & WRITES == 0 {
        return 1;
    }
    e.out.extend_from_slice(bytes);
    if e.out.len() - e.out_start >= AUTO_DRAIN {
        drain(e);
    }
    0
}

/// Writes as much of the buffer as the descriptor takes now; whether it is empty.
fn drain(e: &mut Entry) -> bool {
    while e.out_start < e.out.len() {
        let rest = &e.out[e.out_start..];
        // SAFETY: `rest` is readable.
        let n = unsafe { sys::write(e.fd, rest.as_ptr().cast(), rest.len()) };
        if n > 0 {
            e.out_start += n as usize;
            continue;
        }
        match sys::last_errno() {
            sys::EINTR => continue,
            sys::EAGAIN => return false,
            _ => {
                fail(e, "write");
                e.out.clear();
                e.out_start = 0;
                return true;
            }
        }
    }
    e.out.clear();
    e.out_start = 0;
    true
}

fn write_retry(id: i64, stream: usize, bits: u32) -> bool {
    if bits & task::WAIT_CANCELLED != 0 {
        return true;
    }
    let drained = match slot(&mut streams(), stream as i64) {
        Some(e) => drain(e),
        None => true,
    };
    if drained {
        promise::io_done_unit(id);
    }
    drained
}

/// A promise that finishes when the buffer has drained. A failure is in `msrt_streams_error`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_streams_flush(stream: i64) -> i64 {
    let id = promise::io_new();
    let (drained, fd) = {
        let mut table = streams();
        match slot(&mut table, stream) {
            Some(e) => {
                e.error.clear();
                (drain(e), e.fd)
            }
            None => (true, -1),
        }
    };
    if drained
        || !promise::io_on_ready(id, fd, task::WAIT_WRITE, -1, write_retry, stream as usize)
    {
        promise::io_done_unit(id);
    }
    id
}

/// Bytes accepted and not yet drained.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_streams_buffered(stream: i64) -> i64 {
    slot(&mut streams(), stream).map_or(0, |e| (e.out.len() - e.out_start) as i64)
}

/// The message of the failure that ended the last operation, or an empty string.
///
/// # Safety
/// `out` is writable memory for a string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_streams_error(stream: i64, out: *mut ms_rt_abi::StrVal) {
    let mut table = streams();
    let msg = slot(&mut table, stream).map_or(&[][..], |e| e.error.as_slice());
    // SAFETY: `out` is uninitialised memory for a string.
    unsafe { *out = crate::string::from_bytes(msg) };
}

/// Drains what is buffered (the descriptor may block), closes an owned descriptor and frees the
/// entry. A close of a gone id does nothing.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_streams_close(stream: i64) {
    let mut table = streams();
    let Some(e) = slot(&mut table, stream) else {
        return;
    };
    if e.flags & WRITES != 0 {
        drain(e);
    }
    if e.flags & OWNS != 0 && e.fd >= 0 {
        // SAFETY: the entry owns the descriptor.
        unsafe { sys::close(e.fd) };
    }
    e.live = false;
    e.fd = -1;
    e.out = Vec::new();
    e.out_start = 0;
}
