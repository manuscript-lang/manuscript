//! Failure classification shared by the filesystem natives, for the filesystem natives: errno values become `FileSystemError` cases; anything else is `Failed`
//! with the operation, path and OS error text.
use crate::sys::{self, Errno};
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_FAILED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED};

/// A failed operation: the status code and, for `STATUS_FAILED`, the diagnostic text.
#[derive(Debug, PartialEq, Eq)]
pub struct Fail {
    pub status: u8,
    pub message: Option<Vec<u8>>,
}

pub type Res<T> = Result<T, Fail>;

impl Fail {
    pub fn status(status: u8) -> Fail {
        Fail {
            status,
            message: None,
        }
    }

    pub fn invalid() -> Fail {
        Fail::status(STATUS_INVALID_INPUT)
    }

    pub fn failed(message: &str) -> Fail {
        Fail {
            status: STATUS_FAILED,
            message: Some(message.as_bytes().to_vec()),
        }
    }

    /// A bare system-call failure (`syscall.Errno` text, no operation or path prefix).
    pub fn raw(e: Errno) -> Fail {
        let status = classify(e);
        if status != STATUS_FAILED {
            return Fail::status(status);
        }
        Fail {
            status,
            message: Some(describe(e).into_bytes()),
        }
    }

    /// An operating-system failure of `op` on one path (`open /x: permission denied`).
    pub fn errno(e: Errno, op: &str, path: &[u8]) -> Fail {
        Fail::errno_paths(e, op, &[path])
    }

    pub fn errno_paths(e: Errno, op: &str, paths: &[&[u8]]) -> Fail {
        let status = classify(e);
        if status != STATUS_FAILED {
            return Fail::status(status);
        }
        let mut m: Vec<u8> = Vec::new();
        m.extend_from_slice(op.as_bytes());
        for p in paths {
            m.push(b' ');
            m.extend_from_slice(p);
        }
        m.extend_from_slice(b": ");
        m.extend_from_slice(describe(e).as_bytes());
        Fail {
            status,
            message: Some(m),
        }
    }
}

/// The status an OS error code maps to (`classifyOS`).
pub fn classify(e: Errno) -> u8 {
    sys::classify(e)
}

/// The host's detail text for an OS error code.
pub fn describe(e: Errno) -> String {
    sys::describe(e)
}

/// `readBounded` failure codes mapped to filesystem errors.
pub fn read_failure(limit: bool) -> Fail {
    Fail::status(if limit {
        STATUS_LIMIT_EXCEEDED
    } else {
        STATUS_INVALID_DATA
    })
}
