//! Generic `read_all`, `copy` and `read_line` over user-defined `ReadStream`s.
//!
//! The compiler lowers the read loop itself (it calls the interface's `read`), and this
//! accumulator owns the policy of `io.go`: chunk sizes, validation and limits. Each round asks
//! [`Acc::want`] for the next request size (`0` ends the loop), reads a chunk, and hands it to
//! [`Acc::push`]; the finishing call reports the outcome as a status.

use alloc::boxed::Box;
use alloc::vec::Vec;

use ms_rt_abi::{
    STATUS_FAILED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_NONE,
    STATUS_OK, StrObj, VecVal,
};
use ms_std_rt::{new_string, record_failure, vec_bytes, write_bytes};

const CHUNK: i64 = 32768;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    ReadAll,
    Copy,
    Line,
}

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

fn start(kind: Kind, has_max: u8, max: i64) -> *mut Acc {
    Box::into_raw(Box::new(Acc::new(kind, (has_max != 0).then_some(max))))
}

/// `kind`: 0 `read_all`, 1 `copy`, 2 `read_line`. Freed by the matching `finish`.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_io_acc_new(kind: i64, has_max: u8, max: i64) -> *mut Acc {
    let kind = match kind {
        0 => Kind::ReadAll,
        1 => Kind::Copy,
        _ => Kind::Line,
    };
    start(kind, has_max, max)
}

/// The next read size, or `0` when the loop should stop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_acc_want(a: *const Acc) -> i64 {
    // SAFETY: `a` is a live accumulator.
    unsafe { (*a).want() }
}

/// Accepts a chunk; answers whether the loop continues.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_acc_push(a: *mut Acc, data: *const VecVal) -> u8 {
    // SAFETY: `a` is live and `data` a live byte vector.
    unsafe { (*a).push(vec_bytes(data)) as u8 }
}

/// Frees the accumulator and answers its status.
unsafe fn finish<T>(a: *mut Acc, ok: impl FnOnce(Acc) -> T) -> (u8, Option<T>) {
    // SAFETY: `a` came from `msstd_io_acc_new` and is finished once.
    let acc = unsafe { Box::from_raw(a) };
    let status = acc.status;
    if status == STATUS_OK {
        (status, Some(ok(*acc)))
    } else {
        (status, None)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_acc_finish_bytes(a: *mut Acc, out: *mut VecVal) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (status, bytes) = unsafe { finish(a, |acc| acc.buf) };
    if let Some(b) = bytes {
        // SAFETY: `out` is writable.
        unsafe { write_bytes(&b, out) };
    }
    status
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_acc_finish_count(a: *mut Acc, out: *mut i64) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (status, total) = unsafe { finish(a, |acc| acc.total) };
    if let Some(t) = total {
        // SAFETY: `out` is writable.
        unsafe { *out = t };
    }
    status
}

/// `STATUS_NONE` at end of stream before any byte.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_acc_finish_line(a: *mut Acc, out: *mut *mut StrObj) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (status, line) = unsafe { finish(a, |acc| (acc.buf, acc.done)) };
    let Some((buf, ended)) = line else {
        return status;
    };
    if buf.is_empty() && !ended {
        return STATUS_NONE;
    }
    if core::str::from_utf8(&buf).is_err() {
        return STATUS_INVALID_DATA;
    }
    // SAFETY: `out` is writable.
    unsafe { *out = new_string(&buf) };
    STATUS_OK
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
