//! A host stream over a file descriptor, ported from `hostStream` in `pkg/runtime/io.go`.
//!
//! Reads and writes block in `poll(2)` slices so a pending cancellation interrupts them; bytes a
//! line reader took beyond the current line wait in `pending` for the next read.
use crate::err::describe;
use crate::sys::{self, CPath, Interest};
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt::Write;
use ms_rt_abi::{
    STATUS_CLOSED, STATUS_FAILED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED,
    STATUS_NONE, STATUS_UNAVAILABLE,
};
use ms_std_rt::poll_cancel;

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

unsafe extern "C-unwind" {
    /// Writes out the runtime's buffered standard output (`print`), so streams keep program order.
    fn msrt_io_flush();
}

pub struct Stream {
    pub(crate) fd: sys::Fd,
    /// Standard output and error share the descriptor with the runtime's buffered `print`.
    shares_output: bool,
    owned: bool,
    closed: bool,
    /// Whether reads may block indefinitely (anything that is not a regular file).
    pollable: bool,
    /// The open mode forbids reading or writing, which is `InvalidInput` on every host.
    pub(crate) no_read: bool,
    pub(crate) no_write: bool,
    /// An `@std/fs` file handle: flushing synchronizes the file.
    pub(crate) file: bool,
    pub(crate) name: Vec<u8>,
    pub(crate) pending: Vec<u8>,
}

const DEFAULT_CHUNK: i64 = 64 * 1024;
const POLL_SLICE_MS: i32 = 50;

impl Stream {
    pub fn new(fd: sys::Fd, owned: bool, name: &[u8]) -> Stream {
        let pollable = sys::fstat(fd)
            .map(|st| sys::is_pollable(&st))
            .unwrap_or(true);
        let shares_output = !owned && sys::is_output(fd);
        Stream {
            fd,
            shares_output,
            owned,
            closed: false,
            pollable,
            no_read: false,
            no_write: false,
            file: false,
            name: name.to_vec(),
            pending: Vec::new(),
        }
    }

    /// Standard input (0), output (1) or error (2); the descriptor stays open.
    pub fn standard(which: i64) -> Stream {
        let name: &[u8] = match which {
            0 => b"/dev/stdin",
            1 => b"/dev/stdout",
            _ => b"/dev/stderr",
        };
        Stream::new(sys::standard(which), false, name)
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
        if self.owned {
            return sys::close(self.fd).map_err(|e| IoFail::os("close", &self.name, e));
        }
        Ok(())
    }

    /// Blocks until the descriptor is ready, checking for cancellation between slices.
    fn wait(&self, interest: Interest) {
        if !self.pollable {
            poll_cancel();
            return;
        }
        loop {
            poll_cancel();
            if sys::wait_ready(self.fd, interest, POLL_SLICE_MS) {
                // Ready, hung up, or failed: the next read or write reports the details.
                return;
            }
        }
    }

    fn read_fd(&mut self, buf: &mut [u8]) -> Result<usize, i32> {
        self.wait(Interest::Read);
        sys::read(self.fd, buf)
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
        if !self.pending.is_empty() {
            let take = n.min(self.pending.len());
            let rest = self.pending.split_off(take);
            return Ok(Some(core::mem::replace(&mut self.pending, rest)));
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
            // SAFETY: provided by `ms-rt`.
            unsafe { msrt_io_flush() };
        }
        while !data.is_empty() {
            self.wait_write();
            let end = data.len().min(1 << 20);
            match sys::write(self.fd, &data[..end]) {
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
        if self.file && !self.pending.is_empty() {
            sys::rewind_by(self.fd, self.pending.len());
            self.pending.clear();
        }
    }

    /// `ioReadLine`: one line without its ending, `None` at end of stream.
    pub fn read_line(&mut self, max: Option<i64>) -> IoRes<Option<Vec<u8>>> {
        let max = match max {
            None => i64::MAX,
            Some(v) if v <= 0 => return Err(IoFail::status(STATUS_INVALID_INPUT)),
            Some(v) => v,
        } as u64;
        if let Some(i) = self.pending.iter().position(|&c| c == b'\n')
            && line_length(&self.pending[..i]) < max
        {
            let rest = self.pending.split_off(i + 1);
            let mut line = core::mem::replace(&mut self.pending, rest);
            line.truncate(i);
            return finish_line(line).map(Some);
        }
        let mut b: Vec<u8> = Vec::new();
        loop {
            let mut chunk = core::mem::take(&mut self.pending);
            if chunk.is_empty() {
                match self.read(Some(DEFAULT_CHUNK))? {
                    None if b.is_empty() => return Ok(None),
                    None => break,
                    Some(c) => chunk = c,
                }
            }
            if let Some(i) = chunk.iter().position(|&c| c == b'\n') {
                // An over-long line is dropped; the lines after it stay readable.
                if i + 1 < chunk.len() {
                    self.pending = chunk[i + 1..].to_vec();
                }
                b.extend_from_slice(&chunk[..i]);
                if line_length(&b) >= max {
                    return Err(IoFail::status(STATUS_LIMIT_EXCEEDED));
                }
                break;
            }
            b.extend_from_slice(&chunk);
            if b.len() as u64 > max {
                return Err(IoFail::status(STATUS_LIMIT_EXCEEDED));
            }
        }
        finish_line(b).map(Some)
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        let _ = self.close();
    }
}

/// The length of `line` without a trailing carriage return, which belongs to the line ending.
fn line_length(line: &[u8]) -> u64 {
    match line.last() {
        Some(b'\r') => line.len() as u64 - 1,
        _ => line.len() as u64,
    }
}

fn finish_line(mut line: Vec<u8>) -> IoRes<Vec<u8>> {
    if line.last() == Some(&b'\r') {
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
}
