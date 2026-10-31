//! The Unix calls `std` has no equivalent for: `statfs`, `FICLONE`, `access(2)`, `poll(2)`,
//! no-follow time and mode changes, and a close-on-exec pipe for `ms-std-process`. Everything else
//! lives in the portable layer in `mod.rs`.
#[cfg(test)]
use super::Interest;
use super::{CPath, Errno, FsStat};

/// Runs a libc call returning a negative value on failure, retrying `EINTR`.
fn retry<T: Copy + PartialOrd + Default>(mut call: impl FnMut() -> T) -> Result<T, Errno> {
    loop {
        let r = call();
        if r >= T::default() {
            return Ok(r);
        }
        let e = super::errno();
        if e != libc::EINTR {
            return Err(e);
        }
    }
}

pub fn set_errno(value: Errno) {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    // SAFETY: `__errno_location` returns the calling thread's errno slot.
    unsafe {
        *libc::__errno_location() = value
    };
    #[cfg(target_os = "macos")]
    // SAFETY: `__error` returns the calling thread's errno slot.
    unsafe {
        *libc::__error() = value
    };
}

pub fn access(path: &CPath, mode: i32) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::access(path.as_ptr(), mode) }).map(|_| ())
}

/// Sets the times of a symbolic link itself (`std` only changes the file a link names).
pub fn utimens_nofollow(path: &CPath, atime: (i64, i64), mtime: (i64, i64)) -> Result<(), Errno> {
    let times = [
        libc::timespec {
            tv_sec: atime.0 as _,
            tv_nsec: atime.1 as _,
        },
        libc::timespec {
            tv_sec: mtime.0 as _,
            tv_nsec: mtime.1 as _,
        },
    ];
    // SAFETY: `path` is NUL-terminated and `times` has two entries.
    retry(|| unsafe {
        libc::utimensat(
            libc::AT_FDCWD,
            path.as_ptr(),
            times.as_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    })
    .map(|_| ())
}

pub fn statfs(path: &CPath) -> Result<FsStat, Errno> {
    // SAFETY: zeroed `statfs` is a valid out buffer.
    let mut s: libc::statfs = unsafe { std::mem::zeroed() };
    // SAFETY: `path` is NUL-terminated and `s` writable.
    retry(|| unsafe { libc::statfs(path.as_ptr(), &mut s) })?;
    Ok(FsStat {
        kind: s.f_type as i64,
        block_size: s.f_bsize as i64,
        blocks: s.f_blocks as i64,
        blocks_free: s.f_bfree as i64,
        blocks_available: s.f_bavail as i64,
        files: s.f_files as i64,
        files_free: s.f_ffree as i64,
    })
}

/// A pipe whose descriptors close on exec (and do not block when `nonblocking`), made
/// atomically where `pipe2` exists.
///
/// # Safety
/// Plain system calls on `fds`.
pub unsafe fn pipe_cloexec(fds: &mut [i32; 2], nonblocking: bool) -> i32 {
    #[cfg(target_os = "linux")]
    {
        let flags = libc::O_CLOEXEC | if nonblocking { libc::O_NONBLOCK } else { 0 };
        // SAFETY: `fds` has room for the two descriptors.
        unsafe { libc::pipe2(fds.as_mut_ptr(), flags) }
    }
    #[cfg(not(target_os = "linux"))]
    {
        // SAFETY: `fds` has room for the two descriptors; fcntl calls are on fresh descriptors.
        unsafe {
            if libc::pipe(fds.as_mut_ptr()) != 0 {
                return -1;
            }
            for &fd in fds.iter() {
                libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC);
                if nonblocking {
                    let flags = libc::fcntl(fd, libc::F_GETFL);
                    libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
                }
            }
        }
        0
    }
}

/// Blocks up to `ms` milliseconds until `fd` is ready; `true` when ready, hung up or failed (the
/// next read or write reports the details). Tests only: the runtime parks tasks instead.
#[cfg(test)]
pub fn wait_ready(fd: super::Fd, interest: Interest, ms: i32) -> bool {
    let mut p = libc::pollfd {
        fd,
        events: match interest {
            Interest::Read => libc::POLLIN,
            Interest::Write => libc::POLLOUT,
        },
        revents: 0,
    };
    // SAFETY: one valid `pollfd`.
    unsafe { libc::poll(&mut p, 1, ms) != 0 }
}

/// Linux `FICLONE`: makes `output` share the extents of `input`.
pub fn clone_file(output: super::Fd, input: super::Fd) -> Result<(), Errno> {
    #[cfg(target_os = "linux")]
    {
        // SAFETY: both descriptors are open; FICLONE takes the source descriptor.
        let r = unsafe { libc::ioctl(output, 0x4004_9409 as _, input) };
        if r != 0 {
            return Err(super::errno());
        }
        Ok(())
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (output, input);
        Err(libc::ENOTSUP)
    }
}

/// Changes the mode of a symbolic link itself (macOS only).
pub fn chmod_link(path: &CPath, mode: u32) -> Result<(), Errno> {
    #[cfg(target_os = "macos")]
    {
        // SAFETY: `path` is NUL-terminated.
        if unsafe {
            libc::fchmodat(
                libc::AT_FDCWD,
                path.as_ptr(),
                mode as libc::mode_t,
                libc::AT_SYMLINK_NOFOLLOW,
            )
        } != 0
        {
            return Err(super::errno());
        }
        Ok(())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (path, mode);
        Err(libc::ENOTSUP)
    }
}

/// Fixed wording for an errno, the same on every Unix; `None` for codes without one.
pub fn errno_text(e: Errno) -> Option<&'static str> {
    Some(match e {
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
        _ => return None,
    })
}
