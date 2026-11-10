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
use crate::{alloc, promise, task};
use ms_rt_abi::VecVal;
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
    /// The message of a read failure or terminal write failure. Write failures stay until close:
    /// the unwritten bytes were discarded, so a later empty flush cannot establish success.
    error: Vec<u8>,
    /// Flush promises waiting for the buffer to drain.
    flushes: Vec<i64>,
}

/// The system calls under the table. Unix works on any descriptor; Windows serves the three
/// standard handles through `std::io`, whose calls block the calling thread until they finish,
/// and a child's pipes through the poller's overlapped pipes.
#[cfg(not(windows))]
mod plat {
    use crate::sys;

    pub enum Fail {
        Interrupted,
        WouldBlock,
        Other(i32),
    }

    fn classify() -> Fail {
        match sys::last_errno() {
            sys::EINTR => Fail::Interrupted,
            sys::EAGAIN => Fail::WouldBlock,
            n => Fail::Other(n),
        }
    }

    pub fn set_nonblocking(fd: i32) {
        // SAFETY: plain fcntl calls on a descriptor the caller hands over.
        unsafe {
            let current = sys::fcntl(fd, sys::F_GETFL);
            if current >= 0 {
                sys::fcntl(fd, sys::F_SETFL, current | sys::O_NONBLOCK);
            }
        }
    }

    /// Whether a read of `fd` would not block.
    pub fn readable_now(fd: i32) -> bool {
        let mut p = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: one valid pollfd and a zero timeout.
        unsafe { libc::poll(&mut p, 1, 0) != 0 }
    }

    pub fn read(fd: i32, buf: &mut [u8]) -> Result<usize, Fail> {
        // SAFETY: `buf` is writable for its length.
        let n = unsafe { sys::read(fd, buf.as_mut_ptr().cast(), buf.len()) };
        if n >= 0 {
            Ok(n as usize)
        } else {
            Err(classify())
        }
    }

    pub fn write(fd: i32, buf: &[u8]) -> Result<usize, Fail> {
        // SAFETY: `buf` is readable for its length.
        let n = unsafe { sys::write(fd, buf.as_ptr().cast(), buf.len()) };
        if n >= 0 {
            Ok(n as usize)
        } else {
            Err(classify())
        }
    }

    pub fn write_key(fd: i32) -> i32 {
        fd
    }

    pub fn close(fd: i32) {
        // SAFETY: the entry owns the descriptor.
        unsafe { sys::close(fd) };
    }
}

#[cfg(windows)]
mod plat {
    use crate::glue::pipe;
    use std::io::{Read, Write};

    pub enum Fail {
        Interrupted,
        WouldBlock,
        Other(i32),
    }

    fn classify(e: std::io::Error) -> Fail {
        match e.kind() {
            std::io::ErrorKind::Interrupted => Fail::Interrupted,
            std::io::ErrorKind::WouldBlock => Fail::WouldBlock,
            _ => Fail::Other(e.raw_os_error().unwrap_or(-1)),
        }
    }

    /// The standard handles are shared, so nothing changes their mode; adopted pipes never block.
    pub fn set_nonblocking(_fd: i32) {}

    /// A standard-input read blocks its thread until data or the end arrives; a pipe read
    /// answers `WouldBlock` instead.
    pub fn readable_now(_fd: i32) -> bool {
        true
    }

    /// The poller key a blocked write waits on: an adopted pipe's writer waits on the handle
    /// plus one, so a reader can wait on the same pipe.
    pub fn write_key(fd: i32) -> i32 {
        if pipe::is_adopted(fd as isize) {
            fd + 1
        } else {
            fd
        }
    }

    pub fn read(fd: i32, buf: &mut [u8]) -> Result<usize, Fail> {
        if fd == 0 {
            return std::io::stdin().lock().read(buf).map_err(classify);
        }
        if pipe::is_adopted(fd as isize) {
            return pipe::try_read(fd as isize, buf).map_err(classify);
        }
        Err(Fail::Other(6))
    }

    pub fn write(fd: i32, buf: &[u8]) -> Result<usize, Fail> {
        match fd {
            1 => {
                let mut out = std::io::stdout().lock();
                out.write(buf).and_then(|n| out.flush().map(|()| n))
            }
            2 => {
                let mut err = std::io::stderr().lock();
                err.write(buf).and_then(|n| err.flush().map(|()| n))
            }
            _ if pipe::is_adopted(fd as isize) => pipe::try_write(fd as isize, buf),
            _ => return Err(Fail::Other(6)),
        }
        .map_err(classify)
    }

    /// Closes an adopted pipe the entry owns; the standard handles stay open.
    pub fn close(fd: i32) {
        if pipe::is_adopted(fd as isize) {
            pipe::close(fd as isize);
        }
    }
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
        plat::set_nonblocking(fd as i32);
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

fn fail(e: &mut Entry, what: &str, code: i32) {
    e.error = format!("{what}: os error {code}").into_bytes();
}

enum Step {
    Data(Vec<u8>),
    End,
    Blocked,
    Failed,
}

/// Whether a read of `fd` would not block. A descriptor opened without `NONBLOCK` (the inherited
/// standard input, whose file description is shared with other processes) is polled first so a
/// silent pipe parks the task instead of the thread.
fn readable_now(e: &Entry) -> bool {
    e.flags & NONBLOCK != 0 || plat::readable_now(e.fd)
}

fn try_read(e: &mut Entry) -> Step {
    if !readable_now(e) {
        return Step::Blocked;
    }
    let mut buf = vec![0u8; CHUNK];
    loop {
        match plat::read(e.fd, &mut buf) {
            Ok(0) => return Step::End,
            Ok(n) => {
                buf.truncate(n);
                return Step::Data(buf);
            }
            Err(plat::Fail::Interrupted) => continue,
            Err(plat::Fail::WouldBlock) => return Step::Blocked,
            Err(plat::Fail::Other(code)) => {
                fail(e, "read", code);
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

/// Queues `data`; 0 admitted, 1 closed or not writable. Inspect `msrt_streams_error` for a
/// terminal write failure, including one already observed by an automatic drain. Never waits.
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
    if !e.error.is_empty() {
        return 0;
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
        match plat::write(e.fd, &e.out[e.out_start..]) {
            Ok(0) => {
                fail(e, "write", 0);
                e.out.clear();
                e.out_start = 0;
                return true;
            }
            Ok(n) => e.out_start += n,
            Err(plat::Fail::Interrupted) => continue,
            Err(plat::Fail::WouldBlock) => return false,
            Err(plat::Fail::Other(code)) => {
                fail(e, "write", code);
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
            Some(e) => (drain(e), plat::write_key(e.fd)),
            None => (true, -1),
        }
    };
    if drained || !promise::io_on_ready(id, fd, task::WAIT_WRITE, -1, write_retry, stream as usize)
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

/// The last read failure or the terminal write failure, or an empty string.
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
        plat::close(e.fd);
    }
    e.live = false;
    e.fd = -1;
    e.out = Vec::new();
    e.out_start = 0;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(stream: i64, data: &[u8]) {
        let bytes = VecVal {
            ptr: data.as_ptr().cast_mut(),
            len: data.len(),
            cap: 0,
        };
        // SAFETY: `bytes` borrows the readable input for the duration of the call.
        assert_eq!(unsafe { msrt_streams_write(stream, &bytes) }, 0);
    }

    fn flush(stream: i64) {
        let promise = msrt_streams_flush(stream);
        assert_eq!(promise::msrt_promise_wait(promise, -1), promise::OK);
        promise::msrt_promise_drop(promise);
    }

    #[test]
    fn automatic_write_failures_survive_flush_and_stop_buffering() {
        let _guard = crate::testutil::lock();
        // No platform has a stream at this invalid, unowned descriptor.
        let stream = msrt_streams_open(i64::from(i32::MAX), WRITES);
        write(stream, &vec![0; AUTO_DRAIN]);
        let error = slot(&mut streams(), stream).unwrap().error.clone();
        assert!(error.starts_with(b"write: os error "));
        assert_eq!(msrt_streams_buffered(stream), 0);

        for _ in 0..2 {
            flush(stream);
            assert_eq!(slot(&mut streams(), stream).unwrap().error, error);
            write(stream, b"not queued after failure");
            assert_eq!(msrt_streams_buffered(stream), 0);
        }
        msrt_streams_close(stream);
    }

    #[test]
    fn retried_write_failures_survive_later_flushes() {
        let _guard = crate::testutil::lock();
        let stream = msrt_streams_open(i64::from(i32::MAX), WRITES);
        write(stream, b"buffered until the readiness callback");
        let promise = promise::io_new();
        assert!(write_retry(promise, stream as usize, task::WAIT_WRITE));
        promise::msrt_promise_drop(promise);
        let error = slot(&mut streams(), stream).unwrap().error.clone();
        assert!(error.starts_with(b"write: os error "));
        flush(stream);
        assert_eq!(slot(&mut streams(), stream).unwrap().error, error);
        msrt_streams_close(stream);
    }
}
