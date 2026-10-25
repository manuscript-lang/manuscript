//! Generic `read_all`, `copy` and `read_line` over user-defined `ReadStream`s.
//!
//! The compiler lowers the read loop itself (it calls the interface's `read`), and this
//! accumulator owns the policy of `io.go`: chunk sizes, validation and limits. Each round asks
//! [`Acc::want`] for the next request size (`0` ends the loop), reads a chunk, and hands it to
//! [`Acc::push`]; the finishing call reports the outcome as a status.

use alloc::boxed::Box;
use alloc::vec::Vec;

use ms_rt::ffi::{Mut, Own, Ref, StatusCode, Text, abi_handle, native};
use ms_rt::glue::record_failure;
use ms_rt_abi::{
    STATUS_FAILED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_NONE,
    STATUS_OK,
};

const CHUNK: i64 = 32768;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    ReadAll,
    Copy,
    Line,
}

abi_handle!(Acc);

pub struct Acc {
    kind: Kind,
    max: i64,
    buf: Vec<u8>,
    total: i64,
    status: u8,
    done: bool,
}

impl Acc {
    fn new(kind: Kind, max: Option<i64>) -> Acc {
        let bad = match max {
            Some(m) => m < 0 || (kind == Kind::Line && m == 0),
            None => false,
        };
        Acc {
            kind,
            max: max.unwrap_or(i64::MAX),
            buf: Vec::new(),
            total: 0,
            status: if bad { STATUS_INVALID_INPUT } else { STATUS_OK },
            done: bad,
        }
    }

    fn used(&self) -> i64 {
        match self.kind {
            Kind::Copy => self.total,
            _ => self.buf.len() as i64,
        }
    }

    fn fail(&mut self, status: u8) -> bool {
        self.status = status;
        self.done = true;
        false
    }

    /// The size to request next; `0` when the loop is over.
    fn want(&self) -> i64 {
        if self.done {
            return 0;
        }
        if self.kind == Kind::Line {
            return 1;
        }
        let left = self.max - self.used();
        if left < CHUNK { left + 1 } else { CHUNK }
    }

    /// Accepts one chunk; `false` ends the loop with a failure or a finished line.
    fn push(&mut self, data: &[u8]) -> bool {
        let asked = self.want();
        if self.kind == Kind::Line {
            return self.push_line(data);
        }
        if data.is_empty() || data.len() as i64 > asked {
            record_failure(b"invalid stream chunk".to_vec());
            return self.fail(STATUS_FAILED);
        }
        if data.len() as i64 > self.max - self.used() {
            return self.fail(STATUS_LIMIT_EXCEEDED);
        }
        match self.kind {
            Kind::Copy => self.total += data.len() as i64,
            _ => self.buf.extend_from_slice(data),
        }
        true
    }

    fn push_line(&mut self, data: &[u8]) -> bool {
        if data.len() != 1 {
            record_failure(b"invalid stream chunk".to_vec());
            return self.fail(STATUS_FAILED);
        }
        if data[0] == b'\n' {
            if self.buf.last() == Some(&b'\r') {
                self.buf.pop();
            }
            if self.buf.len() as i64 >= self.max {
                return self.fail(STATUS_LIMIT_EXCEEDED);
            }
            self.done = true;
            return false;
        }
        if self.buf.len() as i64 >= self.max {
            return self.fail(STATUS_LIMIT_EXCEEDED);
        }
        self.buf.push(data[0]);
        true
    }
}

/// `kind`: 0 `read_all`, 1 `copy`, 2 `read_line`. Freed by the matching `finish`.
fn start(kind: i64, has_max: bool, max: i64) -> Own<Acc> {
    let kind = match kind {
        0 => Kind::ReadAll,
        1 => Kind::Copy,
        _ => Kind::Line,
    };
    Own(Box::new(Acc::new(kind, has_max.then_some(max))))
}

/// The accumulator's status once finished; its result is read only when that is `STATUS_OK`.
fn finish<T>(a: Own<Acc>, ok: impl FnOnce(Acc) -> T) -> Result<T, StatusCode> {
    let acc = *a.0;
    match acc.status {
        STATUS_OK => Ok(ok(acc)),
        status => Err(StatusCode(status)),
    }
}

native! {
    fn msstd_io_acc_new(kind: i64, has_max: bool, max: i64) -> Own<Acc> {
        start(kind, has_max, max)
    }

    /// Abandons an accumulator after an I/O error, fault or cancellation.
    fn msstd_io_acc_drop(a: Own<Acc>) -> () {
        drop(a);
    }

    /// The next read size, or `0` when the loop should stop.
    fn msstd_io_acc_want(a: Ref<Acc>) -> i64 {
        a.want()
    }

    /// Accepts a chunk; answers whether the loop continues.
    fn msstd_io_acc_push(a: Mut<Acc>, data: &[u8]) -> bool {
        let mut a = a;
        a.push(data)
    }

    fn msstd_io_acc_finish_bytes(a: Own<Acc>) -> Result<Vec<u8>, StatusCode> {
        finish(a, |acc| acc.buf)
    }

    fn msstd_io_acc_finish_count(a: Own<Acc>) -> Result<i64, StatusCode> {
        finish(a, |acc| acc.total)
    }

    /// `STATUS_NONE` at end of stream before any byte.
    fn msstd_io_acc_finish_line(a: Own<Acc>) -> Result<Text, StatusCode> {
        let (buf, ended) = finish(a, |acc| (acc.buf, acc.done))?;
        if buf.is_empty() && !ended {
            return Err(StatusCode(STATUS_NONE));
        }
        if core::str::from_utf8(&buf).is_err() {
            return Err(StatusCode(STATUS_INVALID_DATA));
        }
        Ok(Text(buf))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed(acc: &mut Acc, chunks: &[&[u8]]) -> u8 {
        for c in chunks {
            if acc.want() == 0 || !acc.push(c) {
                break;
            }
        }
        acc.status
    }

    #[test]
    fn read_all_limits_and_requests() {
        let mut a = Acc::new(Kind::ReadAll, Some(4));
        assert_eq!(a.want(), 5);
        assert_eq!(feed(&mut a, &[b"abc", b"d"]), STATUS_OK);
        assert_eq!(a.want(), 1);
        assert_eq!(a.buf, b"abcd");
        let mut a = Acc::new(Kind::ReadAll, Some(2));
        assert_eq!(feed(&mut a, &[b"abc"]), STATUS_LIMIT_EXCEEDED);
        assert_eq!(Acc::new(Kind::ReadAll, Some(-1)).want(), 0);
        assert_eq!(Acc::new(Kind::ReadAll, None).want(), CHUNK);
    }

    #[test]
    fn lines_end_on_newline_and_strip_carriage_returns() {
        let mut a = Acc::new(Kind::Line, None);
        feed(&mut a, &[b"h", b"i", b"\r", b"\n", b"x"]);
        assert!(a.done);
        assert_eq!(a.buf, b"hi");
        let mut a = Acc::new(Kind::Line, Some(2));
        assert_eq!(feed(&mut a, &[b"a", b"b", b"c"]), STATUS_LIMIT_EXCEEDED);
        assert_eq!(Acc::new(Kind::Line, Some(0)).want(), 0);
    }
}
