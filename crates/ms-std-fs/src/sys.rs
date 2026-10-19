//! Thin, safe wrappers over the libc calls the filesystem natives need. Paths are byte strings; a
//! trailing NUL is added here. Every wrapper retries `EINTR` and reports `errno` on failure.
use alloc::vec::Vec;
use core::ffi::{CStr, c_char, c_int};

pub type Errno = i32;

pub fn errno() -> Errno {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    // SAFETY: `__errno_location` returns the calling thread's errno slot.
    return unsafe { *libc::__errno_location() };
    #[cfg(target_os = "macos")]
    // SAFETY: `__error` returns the calling thread's errno slot.
    return unsafe { *libc::__error() };
}

pub fn set_errno(value: Errno) {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    // SAFETY: as in `errno`.
    unsafe {
        *libc::__errno_location() = value
    };
    #[cfg(target_os = "macos")]
    // SAFETY: as in `errno`.
    unsafe {
        *libc::__error() = value
    };
}

/// A NUL-terminated copy of `path`; `None` when it is empty or contains a NUL.
pub struct CPath(Vec<u8>);

impl CPath {
    pub fn new(path: &[u8]) -> Option<CPath> {
        if path.is_empty() || path.contains(&0) {
            return None;
        }
        let mut v = Vec::with_capacity(path.len() + 1);
        v.extend_from_slice(path);
        v.push(0);
        Some(CPath(v))
    }

    pub fn as_ptr(&self) -> *const c_char {
        self.0.as_ptr() as *const c_char
    }

    pub fn bytes(&self) -> &[u8] {
        &self.0[..self.0.len() - 1]
    }
}

/// Runs a libc call returning a negative value on failure, retrying `EINTR`.
pub fn retry<T: Copy + PartialOrd + Default>(mut call: impl FnMut() -> T) -> Result<T, Errno> {
    loop {
        let r = call();
        if r >= T::default() {
            return Ok(r);
        }
        let e = errno();
        if e != libc::EINTR {
            return Err(e);
        }
    }
}

pub fn open(path: &CPath, flags: c_int, mode: u32) -> Result<c_int, Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::open(path.as_ptr(), flags | libc::O_CLOEXEC, mode as libc::c_uint) })
}

pub fn close(fd: c_int) -> Result<(), Errno> {
    // SAFETY: closing a descriptor we own; `EINTR` on close must not be retried.
    if unsafe { libc::close(fd) } < 0 {
        Err(errno())
    } else {
        Ok(())
    }
}

pub fn read(fd: c_int, buf: &mut [u8]) -> Result<usize, Errno> {
    // SAFETY: `buf` is writable for its length.
    retry(|| unsafe { libc::read(fd, buf.as_mut_ptr() as *mut _, buf.len()) }).map(|n| n as usize)
}

pub fn write(fd: c_int, buf: &[u8]) -> Result<usize, Errno> {
    // SAFETY: `buf` is readable for its length.
    retry(|| unsafe { libc::write(fd, buf.as_ptr() as *const _, buf.len()) }).map(|n| n as usize)
}

pub fn fstat(fd: c_int) -> Result<libc::stat, Errno> {
    // SAFETY: zeroed `stat` is a valid out buffer.
    let mut st: libc::stat = unsafe { core::mem::zeroed() };
    // SAFETY: `st` is writable.
    retry(|| unsafe { libc::fstat(fd, &mut st) }).map(|_| st)
}

pub fn stat(path: &CPath, follow: bool) -> Result<libc::stat, Errno> {
    // SAFETY: zeroed `stat` is a valid out buffer.
    let mut st: libc::stat = unsafe { core::mem::zeroed() };
    // SAFETY: `path` is NUL-terminated and `st` writable.
    retry(|| unsafe {
        if follow {
            libc::stat(path.as_ptr(), &mut st)
        } else {
            libc::lstat(path.as_ptr(), &mut st)
        }
    })
    .map(|_| st)
}

pub fn is_dir(st: &libc::stat) -> bool {
    st.st_mode & libc::S_IFMT == libc::S_IFDIR
}

/// Birth time of a path when the filesystem reports one (Linux `statx`).
#[cfg(target_os = "linux")]
pub fn birth_time(path: &CPath, follow: bool) -> Option<(i64, i64)> {
    // SAFETY: zeroed `statx` is a valid out buffer.
    let mut stx: libc::statx = unsafe { core::mem::zeroed() };
    let flags = if follow { 0 } else { libc::AT_SYMLINK_NOFOLLOW };
    // SAFETY: `path` is NUL-terminated and `stx` writable.
    let r = unsafe {
        libc::statx(
            libc::AT_FDCWD,
            path.as_ptr(),
            flags,
            libc::STATX_BTIME,
            &mut stx,
        )
    };
    (r == 0 && stx.stx_mask & libc::STATX_BTIME != 0)
        .then_some((stx.stx_btime.tv_sec, stx.stx_btime.tv_nsec as i64))
}

#[cfg(not(target_os = "linux"))]
pub fn birth_time(_: &CPath, _: bool) -> Option<(i64, i64)> {
    None
}

pub fn mkdir(path: &CPath, mode: u32) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::mkdir(path.as_ptr(), mode as libc::mode_t) }).map(|_| ())
}

pub fn unlink(path: &CPath) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::unlink(path.as_ptr()) }).map(|_| ())
}

pub fn rmdir(path: &CPath) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::rmdir(path.as_ptr()) }).map(|_| ())
}

pub fn rename(from: &CPath, to: &CPath) -> Result<(), Errno> {
    // SAFETY: both paths are NUL-terminated.
    retry(|| unsafe { libc::rename(from.as_ptr(), to.as_ptr()) }).map(|_| ())
}

pub fn symlink(target: &CPath, path: &CPath) -> Result<(), Errno> {
    // SAFETY: both paths are NUL-terminated.
    retry(|| unsafe { libc::symlink(target.as_ptr(), path.as_ptr()) }).map(|_| ())
}

pub fn link(from: &CPath, to: &CPath) -> Result<(), Errno> {
    // SAFETY: both paths are NUL-terminated.
    retry(|| unsafe { libc::link(from.as_ptr(), to.as_ptr()) }).map(|_| ())
}

pub fn readlink(path: &CPath) -> Result<Vec<u8>, Errno> {
    let mut size = 256;
    loop {
        let mut buf = alloc::vec![0u8; size];
        // SAFETY: `buf` is writable for `size` bytes.
        let n = retry(|| unsafe {
            libc::readlink(path.as_ptr(), buf.as_mut_ptr() as *mut c_char, size)
        })? as usize;
        if n < size {
            buf.truncate(n);
            return Ok(buf);
        }
        size *= 2;
    }
}

pub fn chmod(path: &CPath, mode: u32) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::chmod(path.as_ptr(), mode as libc::mode_t) }).map(|_| ())
}

pub fn chown(path: &CPath, uid: i64, gid: i64, follow: bool) -> Result<(), Errno> {
    let (u, g) = (uid as libc::uid_t, gid as libc::gid_t);
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe {
        if follow {
            libc::chown(path.as_ptr(), u, g)
        } else {
            libc::lchown(path.as_ptr(), u, g)
        }
    })
    .map(|_| ())
}

pub fn truncate(path: &CPath, size: i64) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::truncate(path.as_ptr(), size as libc::off_t) }).map(|_| ())
}

pub fn access(path: &CPath, mode: c_int) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    retry(|| unsafe { libc::access(path.as_ptr(), mode) }).map(|_| ())
}

pub fn utimens(
    path: &CPath,
    atime: (i64, i64),
    mtime: (i64, i64),
    follow: bool,
) -> Result<(), Errno> {
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
    let flags = if follow { 0 } else { libc::AT_SYMLINK_NOFOLLOW };
    // SAFETY: `path` is NUL-terminated and `times` has two entries.
    retry(|| unsafe { libc::utimensat(libc::AT_FDCWD, path.as_ptr(), times.as_ptr(), flags) })
        .map(|_| ())
}

#[derive(Clone, Copy)]
pub struct FsStat {
    pub kind: i64,
    pub block_size: i64,
    pub blocks: i64,
    pub blocks_free: i64,
    pub blocks_available: i64,
    pub files: i64,
    pub files_free: i64,
}

pub fn statfs(path: &CPath) -> Result<FsStat, Errno> {
    // SAFETY: zeroed `statfs` is a valid out buffer.
    let mut s: libc::statfs = unsafe { core::mem::zeroed() };
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

pub fn getcwd() -> Result<Vec<u8>, Errno> {
    let mut size = 256;
    loop {
        let mut buf = alloc::vec![0u8; size];
        set_errno(0);
        // SAFETY: `buf` is writable for `size` bytes.
        let p = unsafe { libc::getcwd(buf.as_mut_ptr() as *mut c_char, size) };
        if !p.is_null() {
            let len = buf.iter().position(|&b| b == 0).unwrap_or(size);
            buf.truncate(len);
            return Ok(buf);
        }
        match errno() {
            libc::ERANGE => size *= 2,
            libc::EINTR => {}
            e => return Err(e),
        }
    }
}

/// Directory entries `(name, d_type)`, excluding `.` and `..`, in on-disk order.
pub fn read_dir(path: &CPath) -> Result<Vec<(Vec<u8>, u8)>, Errno> {
    // SAFETY: `path` is NUL-terminated.
    let dir = unsafe { libc::opendir(path.as_ptr()) };
    if dir.is_null() {
        return Err(errno());
    }
    let mut out = Vec::new();
    let result = loop {
        set_errno(0);
        // SAFETY: `dir` is an open stream.
        let ent = unsafe { libc::readdir(dir) };
        if ent.is_null() {
            break match errno() {
                0 => Ok(()),
                e => Err(e),
            };
        }
        // SAFETY: `d_name` is NUL-terminated within the entry.
        let name = unsafe { CStr::from_ptr((*ent).d_name.as_ptr()) }.to_bytes();
        if name != b"." && name != b".." {
            // SAFETY: `ent` is valid until the next `readdir`.
            out.push((name.to_vec(), unsafe { (*ent).d_type }));
        }
    };
    // SAFETY: `dir` is open and closed once.
    unsafe { libc::closedir(dir) };
    result.map(|_| out)
}

pub const DT_DIR: u8 = libc::DT_DIR;
pub const DT_LNK: u8 = libc::DT_LNK;
pub const DT_UNKNOWN: u8 = libc::DT_UNKNOWN;

pub fn random_u32() -> u32 {
    let mut v = [0u8; 4];
    // SAFETY: `v` is writable for 4 bytes.
    let n = unsafe { libc::getrandom(v.as_mut_ptr() as *mut _, 4, 0) };
    if n == 4 {
        u32::from_ne_bytes(v)
    } else {
        (&v as *const _ as usize as u32) ^ (errno() as u32)
    }
}

pub fn env(name: &CStr) -> Option<Vec<u8>> {
    // SAFETY: `name` is NUL-terminated.
    let p = unsafe { libc::getenv(name.as_ptr()) };
    if p.is_null() {
        return None;
    }
    // SAFETY: `getenv` returns a NUL-terminated string.
    Some(unsafe { CStr::from_ptr(p) }.to_bytes().to_vec())
}

/// Birth time of an open descriptor when the filesystem reports one (Linux `statx`).
#[cfg(target_os = "linux")]
pub fn birth_time_fd(fd: c_int) -> Option<(i64, i64)> {
    // SAFETY: zeroed `statx` is a valid out buffer.
    let mut stx: libc::statx = unsafe { core::mem::zeroed() };
    // SAFETY: an empty path with AT_EMPTY_PATH names the descriptor itself; `stx` is writable.
    let r = unsafe {
        libc::statx(
            fd,
            c"".as_ptr(),
            libc::AT_EMPTY_PATH,
            libc::STATX_BTIME,
            &mut stx,
        )
    };
    (r == 0 && stx.stx_mask & libc::STATX_BTIME != 0)
        .then_some((stx.stx_btime.tv_sec, stx.stx_btime.tv_nsec as i64))
}

#[cfg(not(target_os = "linux"))]
pub fn birth_time_fd(_: c_int) -> Option<(i64, i64)> {
    None
}
