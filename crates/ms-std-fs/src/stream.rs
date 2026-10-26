//! A host stream over a file descriptor.
//!
//! Reads and writes block in `poll(2)` slices so a pending cancellation interrupts them; bytes a
//! line reader took beyond the current line wait in `pending` for the next read.
use crate::err::describe;
use crate::ops::offload;
use crate::sys::{self, CPath, Interest};
use alloc::borrow::Cow;
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt::Write;
use core::sync::atomic::{AtomicU8, Ordering};
use ms_rt::glue::{poll_cancel, stash_stdin_pending, take_stdin_pending};
use ms_rt_abi::{
    STATUS_CLOSED, STATUS_FAILED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED,
    STATUS_NONE, STATUS_UNAVAILABLE,
};

/// The `IoError` outcome of an operation: a status and, for `STATUS_FAILED`, its text.
#[derive(Debug, PartialEq, Eq)]
pub struct IoFail {
    pub status: u8,
    pub message: Vec<u8>,
}

pub type IoRes<T> = Result<T, IoFail>;

impl IoFail {
    pub fn status(status: u8) -> IoFail {
        IoFail {
            status,
            message: Vec::new(),
        }
    }

    pub(crate) fn os(op: &str, name: &[u8], errno: i32) -> IoFail {
        let mut m = String::new();
        let _ = write!(m, "{} ", op);
        let mut bytes = m.into_bytes();
        bytes.extend_from_slice(name);
        bytes.extend_from_slice(b": ");
        bytes.extend_from_slice(describe(errno).as_bytes());
        IoFail {
            status: STATUS_FAILED,
            message: bytes,
        }
    }
}

use ms_rt::io::msrt_io_flush;

ms_rt::ffi::abi_handle!(Stream);

pub struct Stream {
    pub(crate) fd: sys::Fd,
    /// Standard output and error share the descriptor with the runtime's buffered `print`.
    shares_output: bool,
    owned: bool,
    closed: bool,
    /// Whether reads may block indefinitely (anything that is not a regular file).
    pollable: bool,
    /// An overlapped pipe the runtime poller adopted (a child's piped stream): reads and writes
    /// park on the poller instead of being checked in slices.
    #[cfg(windows)]
    adopted: bool,
    /// The open mode forbids reading or writing, which is `InvalidInput` on every host.
    pub(crate) no_read: bool,
    pub(crate) no_write: bool,
    /// An `@std/fs` file handle: flushing synchronizes the file.
    pub(crate) file: bool,
    /// The path for error messages; standard streams borrow a constant.
    pub(crate) name: Cow<'static, [u8]>,
    /// Read-ahead bytes, from `head` on; a line reader consumes them by advancing `head`.
    pub(crate) pending: Vec<u8>,
    head: usize,
}

const DEFAULT_CHUNK: i64 = 64 * 1024;
#[cfg(any(windows, test))]
const POLL_SLICE_MS: i32 = 50;

impl Stream {
    pub fn new(fd: sys::Fd, owned: bool, name: &[u8]) -> Stream {
        let pollable = sys::fstat(fd)
            .map(|st| sys::is_pollable(&st))
            .unwrap_or(true);
        Stream::with_pollable(fd, owned, Cow::Owned(name.to_vec()), pollable)
    }

    fn with_pollable(fd: sys::Fd, owned: bool, name: Cow<'static, [u8]>, pollable: bool) -> Stream {
        let shares_output = !owned && sys::is_output(fd);
        Stream {
            fd,
            shares_output,
            owned,
            closed: false,
            pollable,
            #[cfg(windows)]
            adopted: ms_rt::glue::pipe::is_adopted(fd),
            no_read: false,
            no_write: false,
            file: false,
            name,
            pending: Vec::new(),
            head: 0,
        }
    }

    /// Standard input (0), output (1) or error (2); the descriptor stays open.
    pub fn standard(which: i64) -> Stream {
        let name: &'static [u8] = match which {
            0 => b"/dev/stdin",
            1 => b"/dev/stdout",
            _ => b"/dev/stderr",
        };
        // Programs call `stdin()` once per read: classify each standard descriptor once, not per handle.
        static KIND: [AtomicU8; 3] = [const { AtomicU8::new(0) }; 3];
        let fd = sys::standard(which);
        let slot = &KIND[which.clamp(0, 2) as usize];
        let pollable = match slot.load(Ordering::Relaxed) {
            1 => false,
            2 => true,
            _ => {
                let p = sys::fstat(fd)
                    .map(|st| sys::is_pollable(&st))
                    .unwrap_or(true);
                slot.store(if p { 2 } else { 1 }, Ordering::Relaxed);
                p
            }
        };
        let mut stream = Stream::with_pollable(fd, false, Cow::Borrowed(name), pollable);
        if which == 0 {
            // A new standard-input handle picks up what the previous one read ahead.
            (stream.pending, stream.head) = take_stdin_pending();
        }
        stream
    }

    /// Picks up what standard-input handles dropped since this one was made had read ahead.
    pub fn take_stashed(&mut self) {
        let (bytes, head) = take_stdin_pending();
        if head >= bytes.len() {
            return;
        }
        if self.available().is_empty() {
            (self.pending, self.head) = (bytes, head);
        } else {
            self.pending.extend_from_slice(&bytes[head..]);
        }
    }

    fn available(&self) -> &[u8] {
        &self.pending[self.head..]
    }

    fn consume(&mut self, n: usize) {
        self.head += n;
        if self.head >= self.pending.len() {
            self.pending.clear();
            self.head = 0;
        }
    }

    fn take_pending(&mut self) -> Vec<u8> {
        let mut bytes = core::mem::take(&mut self.pending);
        bytes.drain(..self.head);
        self.head = 0;
        bytes
    }

    /// Opens a file read-only; every failure is `Unavailable` except an embedded NUL.
    pub fn open(path: &[u8]) -> IoRes<Stream> {
        if path.contains(&0) {
            return Err(IoFail::status(STATUS_INVALID_INPUT));
        }
        if path.is_empty() {
            return Err(IoFail::status(STATUS_UNAVAILABLE));
        }
        let c = CPath::new(path).ok_or(IoFail::status(STATUS_INVALID_INPUT))?;
        match sys::open(&c, sys::O_RDONLY, 0) {
            Ok(fd) => Ok(Stream::new(fd, true, path)),
            Err(_) => Err(IoFail::status(STATUS_UNAVAILABLE)),
        }
    }

    /// A stream over an `@std/fs` file handle opened with the given access mode.
    pub fn file_handle(fd: sys::Fd, flags: i32, name: &[u8]) -> Stream {
        let mut s = Stream::new(fd, true, name);
        s.no_read = sys::write_only(flags);
        s.no_write = sys::read_only(flags);
        s.file = true;
        s
    }

    pub fn is_closed(&self) -> bool {
        self.closed
    }

    /// Releases the descriptor of an owned stream once; later calls do nothing.
    pub fn close(&mut self) -> Result<(), IoFail> {
        if self.closed {
            return Ok(());
        }
        self.closed = true;
        #[cfg(windows)]
        if self.adopted {
            ms_rt::glue::pipe::close(self.fd);
            return Ok(());
        }
        if self.owned {
            return sys::close(self.fd).map_err(|e| IoFail::os("close", &self.name, e));
        }
        Ok(())
    }

    /// Blocks until the descriptor is ready. The task parks, so other tasks (a server's
    /// handlers) keep running, and a stop request unwinds.
    fn wait(&self, interest: Interest) {
        if !self.pollable {
            poll_cancel();
            return;
        }
        #[cfg(all(unix, not(test)))]
        {
            let events = match interest {
                Interest::Read => ms_rt::glue::WAIT_READ,
                Interest::Write => ms_rt::glue::WAIT_WRITE,
            };
            // Ready, hung up, or failed: the next read or write reports the details.
            ms_rt::glue::task_wait_fd(self.fd, events, -1);
        }
        // Tests run on many threads, which the runtime's scheduler does not support; Windows
        // pipes and consoles cannot be polled, so they are checked in short slices.
        #[cfg(any(windows, test))]
        loop {
            poll_cancel();
            // A slice on the blocking pool parks this task, so others run meanwhile.
            let ready = offload((self.fd, interest), &[], |&(fd, interest), _| {
                sys::wait_ready(fd, interest, POLL_SLICE_MS)
            });
            if ready {
                // Ready, hung up, or failed: the next read or write reports the details.
                return;
            }
        }
    }

    /// Whether the descriptor is a regular file, whose reads and writes cannot be waited on:
    /// they run on a blocking-pool thread when other tasks could use the time.
    pub(crate) fn regular(&self) -> bool {
        !self.pollable
    }

    /// One `read(2)`; a regular file reads on the blocking pool.
    pub(crate) fn read_raw(&self, buf: &mut [u8]) -> Result<usize, i32> {
        if !self.regular() {
            return sys::read(self.fd, buf);
        }
        let read = offload((self.fd, buf.len()), &[], |&(fd, len), _| {
            let mut buf = alloc::vec![0u8; len];
            sys::read(fd, &mut buf).map(|n| {
                buf.truncate(n);
                buf
            })
        })?;
        buf[..read.len()].copy_from_slice(&read);
        Ok(read.len())
    }

    /// One `write(2)`; a regular file writes on the blocking pool.
    pub(crate) fn write_raw(&self, bytes: &[u8]) -> Result<usize, i32> {
        if !self.regular() {
            return sys::write(self.fd, bytes);
        }
        offload(self.fd, bytes, |&fd, bytes| sys::write(fd, bytes))
    }

    fn read_fd(&mut self, buf: &mut [u8]) -> Result<usize, i32> {
        #[cfg(windows)]
        if self.adopted {
            return ms_rt::glue::pipe::read(self.fd, buf)
                .map_err(|e| e.raw_os_error().unwrap_or(0));
        }
        self.wait(Interest::Read);
        self.read_raw(buf)
    }

    /// One read of up to `max` bytes: `None` at end of stream.
    pub fn read(&mut self, max: Option<i64>) -> IoRes<Option<Vec<u8>>> {
        if self.closed {
            return Err(IoFail::status(STATUS_CLOSED));
        }
        poll_cancel();
        if self.no_read {
            return Err(IoFail::status(STATUS_INVALID_INPUT));
        }
        let n = match max {
            None => DEFAULT_CHUNK,
            Some(v) if v <= 0 => return Err(IoFail::status(STATUS_INVALID_INPUT)),
            Some(v) => v.min(DEFAULT_CHUNK),
        } as usize;
        if !self.available().is_empty() {
            let take = n.min(self.available().len());
            let out = self.available()[..take].to_vec();
            self.consume(take);
            return Ok(Some(out));
        }
        let mut data = alloc::vec![0u8; n];
        match self.read_fd(&mut data) {
            Ok(0) => Ok(None),
            Ok(k) => {
                data.truncate(k);
                Ok(Some(data))
            }
            Err(e) => Err(IoFail::os("read", &self.name, e)),
        }
    }

    pub fn write(&mut self, mut data: &[u8]) -> IoRes<()> {
        if self.closed {
            return Err(IoFail::status(STATUS_CLOSED));
        }
        poll_cancel();
        if self.no_write {
            return Err(IoFail::status(STATUS_INVALID_INPUT));
        }
        self.rewind();
        if self.shares_output {
            msrt_io_flush();
        }
        #[cfg(windows)]
        if self.adopted {
            return ms_rt::glue::pipe::write(self.fd, data)
                .map_err(|e| IoFail::os("write", &self.name, e.raw_os_error().unwrap_or(0)));
        }
        while !data.is_empty() {
            self.wait_write();
            let end = data.len().min(1 << 20);
            match self.write_raw(&data[..end]) {
                Ok(0) => {
                    return Err(IoFail {
                        status: STATUS_FAILED,
                        message: b"short write".to_vec(),
                    });
                }
                Ok(k) => data = &data[k..],
                Err(e) if sys::would_block(e) => continue,
                Err(e) => return Err(IoFail::os("write", &self.name, e)),
            }
        }
        Ok(())
    }

    fn wait_write(&self) {
        if self.pollable {
            self.wait(Interest::Write);
        } else {
            poll_cancel();
        }
    }

    pub fn flush(&mut self) -> IoRes<()> {
        if self.closed {
            return Err(IoFail::status(STATUS_CLOSED));
        }
        poll_cancel();
        if self.file {
            sys::fsync(self.fd).map_err(|e| IoFail::os("sync", &self.name, e))?;
        }
        Ok(())
    }

    /// Returns read-ahead bytes to the file so position-based operations see them.
    pub(crate) fn rewind(&mut self) {
        if self.file && !self.available().is_empty() {
            sys::rewind_by(self.fd, self.available().len());
            self.pending.clear();
            self.head = 0;
        }
    }

    /// `ioReadLine`: one line without its ending, `None` at end of stream.
    pub fn read_line(&mut self, max: Option<i64>) -> IoRes<Option<Vec<u8>>> {
        let max = match max {
            None => i64::MAX,
            Some(v) if v <= 0 => return Err(IoFail::status(STATUS_INVALID_INPUT)),
            Some(v) => v,
        } as u64;
        if let Some(i) = find_newline(self.available())
            && line_length(&self.available()[..i]) < max
        {
            let line = self.available()[..i].to_vec();
            self.consume(i + 1);
            return finish_line(line, true).map(Some);
        }
        let mut b: Vec<u8> = Vec::new();
        let mut terminated = false;
        loop {
            let mut chunk = self.take_pending();
            if chunk.is_empty() {
                match self.read(Some(DEFAULT_CHUNK))? {
                    None if b.is_empty() => return Ok(None),
                    None => break,
                    Some(c) => chunk = c,
                }
            }
            if let Some(i) = find_newline(&chunk) {
                // An over-long line is dropped; the lines after it stay readable.
                if i + 1 < chunk.len() {
                    self.pending = chunk[i + 1..].to_vec();
                    self.head = 0;
                }
                b.extend_from_slice(&chunk[..i]);
                if line_length(&b) >= max {
                    return Err(IoFail::status(STATUS_LIMIT_EXCEEDED));
                }
                terminated = true;
                break;
            }
            b.extend_from_slice(&chunk);
            if b.len() as u64 > max {
                return Err(IoFail::status(STATUS_LIMIT_EXCEEDED));
            }
        }
        finish_line(b, terminated).map(Some)
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        if self.fd == sys::standard(0) && !self.owned && !self.available().is_empty() {
            stash_stdin_pending(core::mem::take(&mut self.pending), self.head);
            self.head = 0;
        }
        let _ = self.close();
    }
}

/// Index of the first `\n`, scanning eight bytes per step.
fn find_newline(buf: &[u8]) -> Option<usize> {
    const LO: u64 = 0x0101_0101_0101_0101;
    const HI: u64 = 0x8080_8080_8080_8080;
    const NL: u64 = LO * b'\n' as u64;
    let (chunks, rest) = buf.as_chunks::<8>();
    let mut at = 0;
    for c in chunks {
        let x = u64::from_le_bytes(*c) ^ NL;
        let zero = x.wrapping_sub(LO) & !x & HI;
        if zero != 0 {
            return Some(at + (zero.trailing_zeros() / 8) as usize);
        }
        at += 8;
    }
    rest.iter().position(|&c| c == b'\n').map(|i| at + i)
}

/// The length of `line` without a trailing carriage return, which belongs to the line ending.
fn line_length(line: &[u8]) -> u64 {
    match line.last() {
        Some(b'\r') => line.len() as u64 - 1,
        _ => line.len() as u64,
    }
}

fn finish_line(mut line: Vec<u8>, terminated: bool) -> IoRes<Vec<u8>> {
    if terminated && line.last() == Some(&b'\r') {
        line.pop();
    }
    if core::str::from_utf8(&line).is_err() {
        return Err(IoFail::status(STATUS_INVALID_DATA));
    }
    Ok(line)
}

pub const NONE: u8 = STATUS_NONE;

impl From<IoFail> for crate::err::Fail {
    fn from(f: IoFail) -> Self {
        crate::err::Fail {
            status: f.status,
            message: (!f.message.is_empty()).then_some(f.message),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pipe() -> (sys::Fd, sys::Fd) {
        sys::pipe()
    }

    #[test]
    fn many_lines_from_one_chunk_and_stashed_read_ahead() {
        let (r, w) = pipe();
        let mut input = Stream::new(r, true, b"pipe");
        let mut output = Stream::new(w, true, b"pipe");
        output.write(b"a\nbb\nccc\n").unwrap();
        output.close().unwrap();
        assert_eq!(input.read_line(None).unwrap().unwrap(), b"a");
        assert_eq!(input.read(Some(2)).unwrap().unwrap(), b"bb");
        stash_stdin_pending(core::mem::take(&mut input.pending), input.head);
        let (bytes, head) = take_stdin_pending();
        assert_eq!(&bytes[head..], b"\nccc\n");
        assert!(take_stdin_pending().0.is_empty());
    }

    #[test]
    fn lines_chunks_and_limits() {
        let (r, w) = pipe();
        let mut input = Stream::new(r, true, b"pipe");
        let mut output = Stream::new(w, true, b"pipe");
        output.write(b"one\r\ntwo\nlong line here\nlast").unwrap();
        output.close().unwrap();
        assert_eq!(input.read_line(None).unwrap().unwrap(), b"one");
        assert_eq!(input.read_line(Some(5)).unwrap().unwrap(), b"two");
        assert_eq!(
            input.read_line(Some(5)).unwrap_err().status,
            STATUS_LIMIT_EXCEEDED
        );
        assert_eq!(input.read_line(None).unwrap().unwrap(), b"last");
        assert_eq!(input.read_line(None).unwrap(), None);
        assert_eq!(
            input.read(Some(0)).unwrap_err().status,
            STATUS_INVALID_INPUT
        );
        input.close().unwrap();
        assert_eq!(input.read(None).unwrap_err().status, STATUS_CLOSED);
        assert_eq!(output.write(b"x").unwrap_err().status, STATUS_CLOSED);
    }

    #[test]
    fn invalid_utf8_line_and_read_ahead() {
        let (r, w) = pipe();
        let mut input = Stream::new(r, true, b"pipe");
        let mut output = Stream::new(w, true, b"pipe");
        output.write(b"ab\n\xff\nrest").unwrap();
        output.close().unwrap();
        assert_eq!(input.read_line(None).unwrap().unwrap(), b"ab");
        assert_eq!(
            input.read_line(None).unwrap_err().status,
            STATUS_INVALID_DATA
        );
        assert_eq!(input.read(Some(2)).unwrap().unwrap(), b"re");
        assert_eq!(input.read(None).unwrap().unwrap(), b"st");
        assert_eq!(input.read(None).unwrap(), None);
    }

    #[test]
    fn find_newline_matches_a_plain_scan() {
        for len in 0..40usize {
            for at in 0..=len {
                let mut buf = vec![b'a'; len];
                if at < len {
                    buf[at] = b'\n';
                    if at + 3 < len {
                        buf[at + 3] = b'\n';
                    }
                    if at > 0 {
                        buf[at - 1] = 0x0b; // one below '\n' must not match
                    }
                }
                assert_eq!(
                    find_newline(&buf),
                    buf.iter().position(|&c| c == b'\n'),
                    "{buf:?}"
                );
            }
        }
    }

    #[test]
    fn open_reports_unavailable() {
        assert_eq!(
            Stream::open(b"/definitely/missing").err().unwrap().status,
            STATUS_UNAVAILABLE
        );
        assert_eq!(
            Stream::open(b"a\0b").err().unwrap().status,
            STATUS_INVALID_INPUT
        );
        assert_eq!(Stream::open(b"").err().unwrap().status, STATUS_UNAVAILABLE);
        #[cfg(target_os = "linux")]
        {
            let mut f = Stream::open(b"/proc/self/status").unwrap();
            assert!(f.read(None).unwrap().is_some());
        }
    }

    #[test]
    fn an_unterminated_carriage_return_is_line_content() {
        for text in [b"\r".as_slice(), b"tail\r", b"tail\r\r"] {
            let (r, w) = pipe();
            let mut input = Stream::new(r, true, b"pipe");
            let mut output = Stream::new(w, true, b"pipe");
            output.write(b"first\n").unwrap();
            output.write(text).unwrap();
            output.close().unwrap();
            assert_eq!(input.read_line(None).unwrap().unwrap(), b"first");
            assert_eq!(input.read_line(None).unwrap().unwrap(), text);
            assert_eq!(input.read_line(None).unwrap(), None);
        }
    }
}
