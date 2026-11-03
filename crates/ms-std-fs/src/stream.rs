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
use ms_rt::glue::poll_cancel;
use ms_rt_abi::{
    STATUS_CLOSED, STATUS_FAILED, STATUS_INVALID_INPUT, STATUS_NONE, STATUS_UNAVAILABLE,
};

/// The `Error` outcome of an operation: a status and, for `STATUS_FAILED`, its text.
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
    /// Opened for append: the host ignores a positioned write's offset, so it is `InvalidInput`.
    pub(crate) append: bool,
    /// An `@std/fs` file handle: flushing synchronizes the file.
    pub(crate) file: bool,
    /// The path for error messages; standard streams borrow a constant.
    pub(crate) name: Cow<'static, [u8]>,
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
            append: false,
            file: false,
            name,
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
        Stream::with_pollable(fd, false, Cow::Borrowed(name), pollable)
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
        match crate::ops::open_waitless(&c, sys::O_RDONLY, 0) {
            Ok(fd) => Ok(Stream::new(fd, true, path)),
            Err(_) => Err(IoFail::status(STATUS_UNAVAILABLE)),
        }
    }

    /// A stream over an `@std/fs` file handle opened with the given access mode.
    pub fn file_handle(fd: sys::Fd, flags: i32, name: &[u8]) -> Stream {
        let mut s = Stream::new(fd, true, name);
        s.no_read = sys::write_only(flags);
        s.no_write = sys::read_only(flags);
        s.append = flags & sys::O_APPEND != 0;
        s.file = true;
        s
    }

    /// A second handle over a duplicate of this file's descriptor, closed on its own. It shares
    /// the file position, but not bytes this handle already read ahead.
    pub fn duplicate(&self) -> Result<Stream, sys::Errno> {
        let fd = sys::duplicate(self.fd)?;
        let mut s = Stream::with_pollable(fd, true, self.name.clone(), self.pollable);
        s.no_read = self.no_read;
        s.no_write = self.no_write;
        s.append = self.append;
        s.file = self.file;
        Ok(s)
    }

    pub fn is_closed(&self) -> bool {
        self.closed
    }

    /// Hands the descriptor of an owned stream to the caller and retires the stream without
    /// closing it; -1 when the stream is closed, borrowed or not a plain descriptor (an adopted
    /// Windows pipe).
    pub fn take_fd(&mut self) -> i64 {
        #[cfg(windows)]
        if self.adopted {
            return -1;
        }
        if self.closed || !self.owned {
            return -1;
        }
        self.closed = true;
        i64::from(self.fd as i32)
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
}

impl Drop for Stream {
    fn drop(&mut self) {
        let _ = self.close();
    }
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
    fn close_reports_release_errors_and_retires_the_stream() {
        // This positive descriptor/handle cannot name an open file. No resource is acquired,
        // and the failed release must not be hidden by File's infallible destructor.
        let mut stream =
            Stream::with_pollable(sys::Fd::MAX, true, Cow::Borrowed(b"invalid-handle"), true);
        let failure = stream.close().unwrap_err();
        assert_eq!(failure.status, STATUS_FAILED);
        assert!(failure.message.starts_with(b"close invalid-handle: "));
        assert!(stream.is_closed());
        assert_eq!(stream.read(None).unwrap_err().status, STATUS_CLOSED);
        assert_eq!(stream.write(b"x").unwrap_err().status, STATUS_CLOSED);
        assert_eq!(stream.flush().unwrap_err().status, STATUS_CLOSED);
        assert_eq!(stream.close(), Ok(()));
    }
}
