//! Failure classification shared by the filesystem natives, following `classifyOS` in
//! `pkg/runtime/fs.go`: errno values become `FileSystemError` cases; anything else is `Failed`
//! with Go's `*PathError` text.
use crate::sys::Errno;
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt::Write;
use ms_rt_abi::{
    STATUS_ALREADY_EXISTS, STATUS_FAILED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT,
    STATUS_LIMIT_EXCEEDED, STATUS_NOT_EMPTY, STATUS_NOT_FOUND, STATUS_PERMISSION_DENIED,
    STATUS_UNSUPPORTED,
};

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

pub fn classify(e: Errno) -> u8 {
    match e {
        libc::ENOSYS | libc::ENOTSUP => STATUS_UNSUPPORTED,
        libc::ENOENT => STATUS_NOT_FOUND,
        libc::ENOTEMPTY => STATUS_NOT_EMPTY,
        libc::EEXIST => STATUS_ALREADY_EXISTS,
        libc::EISDIR | libc::ENOTDIR | libc::EBADF | libc::EINVAL => STATUS_INVALID_INPUT,
        libc::EACCES | libc::EPERM => STATUS_PERMISSION_DENIED,
        _ => STATUS_FAILED,
    }
}

/// Go's text for an errno (`syscall.Errno.Error`).
pub fn describe(e: Errno) -> String {
    let text = match e {
        libc::EPERM => "operation not permitted",
        libc::ENOENT => "no such file or directory",
        libc::ESRCH => "no such process",
        libc::EINTR => "interrupted system call",
        libc::EIO => "input/output error",
        libc::ENXIO => "no such device or address",
        libc::E2BIG => "argument list too long",
        libc::ENOEXEC => "exec format error",
        libc::EBADF => "bad file descriptor",
        libc::ECHILD => "no child processes",
        libc::EAGAIN => "resource temporarily unavailable",
        libc::ENOMEM => "cannot allocate memory",
        libc::EACCES => "permission denied",
        libc::EFAULT => "bad address",
        libc::EBUSY => "device or resource busy",
        libc::EEXIST => "file exists",
        libc::EXDEV => "invalid cross-device link",
        libc::ENODEV => "no such device",
        libc::ENOTDIR => "not a directory",
        libc::EISDIR => "is a directory",
        libc::EINVAL => "invalid argument",
        libc::ENFILE => "too many open files in system",
        libc::EMFILE => "too many open files",
        libc::ENOTTY => "inappropriate ioctl for device",
        libc::ETXTBSY => "text file busy",
        libc::EFBIG => "file too large",
        libc::ENOSPC => "no space left on device",
        libc::ESPIPE => "illegal seek",
        libc::EROFS => "read-only file system",
        libc::EMLINK => "too many links",
        libc::EPIPE => "broken pipe",
        libc::ERANGE => "numerical result out of range",
        libc::ENAMETOOLONG => "file name too long",
        libc::ENOSYS => "function not implemented",
        libc::ENOTEMPTY => "directory not empty",
        libc::ELOOP => "too many levels of symbolic links",
        libc::EDQUOT => "disk quota exceeded",
        libc::ENOTSUP => "operation not supported",
        libc::ECONNRESET => "connection reset by peer",
        libc::ETIMEDOUT => "connection timed out",
        _ => {
            let mut s = String::new();
            let _ = write!(s, "errno {e}");
            return s;
        }
    };
    String::from(text)
}

/// `readBounded` failure codes mapped to filesystem errors.
pub fn read_failure(limit: bool) -> Fail {
    Fail::status(if limit {
        STATUS_LIMIT_EXCEEDED
    } else {
        STATUS_INVALID_DATA
    })
}
