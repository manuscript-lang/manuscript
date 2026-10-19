//! Thin, safe wrappers over the libc calls the filesystem natives need. Paths are byte strings; a
//! trailing NUL is added here. Every wrapper retries `EINTR` and reports `errno` on failure.
use super::{DirEntries, Errno, FsStat, Interest, Stat};
use alloc::string::String;
use alloc::vec::Vec;
use core::ffi::{CStr, c_char, c_int};
use core::fmt::Write;

/// Host file descriptors.
pub type Fd = c_int;

/// The value of a descriptor that is not open.
pub const INVALID_FD: Fd = -1;

pub use libc::{
    EAGAIN, EEXIST, EINVAL, EIO, ELOOP, ENOENT, ENOTDIR, O_APPEND, O_CREAT, O_EXCL, O_RDONLY,
    O_RDWR, O_TRUNC, O_WRONLY,
};

/// `true` when `e` says the path does not exist.
pub fn is_not_found(e: Errno) -> bool {
    e == libc::ENOENT
}

/// `true` when `e` says a path component is not a directory.
pub fn is_not_dir(e: Errno) -> bool {
    e == libc::ENOTDIR
}

/// `true` when `e` says the path already exists.
pub fn is_exists(e: Errno) -> bool {
    e == libc::EEXIST
}

/// `true` when the access mode of `flags` forbids reading.
pub fn write_only(flags: i32) -> bool {
    flags & libc::O_ACCMODE == libc::O_WRONLY
}

/// `true` when the access mode of `flags` forbids writing.
pub fn read_only(flags: i32) -> bool {
    flags & libc::O_ACCMODE == libc::O_RDONLY
}

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

fn convert(st: &libc::stat) -> Stat {
    Stat {
        mode: st.st_mode as u32,
        size: st.st_size as i64,
        modified: (st.st_mtime as i64, st.st_mtime_nsec as i64),
        accessed: (st.st_atime as i64, st.st_atime_nsec as i64),
        changed: (st.st_ctime as i64, st.st_ctime_nsec as i64),
        block_size: st.st_blksize as u64,
        blocks: st.st_blocks as u64,
        rdev: st.st_rdev as u64,
        device: st.st_dev as u64,
        inode: st.st_ino as u64,
        links: st.st_nlink as u64,
        uid: st.st_uid as u64,
        gid: st.st_gid as u64,
    }
}

pub fn fstat(fd: c_int) -> Result<Stat, Errno> {
    // SAFETY: zeroed `stat` is a valid out buffer.
    let mut st: libc::stat = unsafe { core::mem::zeroed() };
    // SAFETY: `st` is writable.
    retry(|| unsafe { libc::fstat(fd, &mut st) }).map(|_| convert(&st))
}

pub fn stat(path: &CPath, follow: bool) -> Result<Stat, Errno> {
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
    .map(|_| convert(&st))
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

/// An open directory stream.
pub struct Dir {
    dir: *mut libc::DIR,
}

impl Dir {
    pub fn open(path: &CPath) -> Result<Dir, Errno> {
        // SAFETY: `path` is NUL-terminated.
        let dir = unsafe { libc::opendir(path.as_ptr()) };
        if dir.is_null() {
            return Err(errno());
        }
        Ok(Dir { dir })
    }

    /// The next entry `(name, kind)` excluding `.` and `..`, in on-disk order; `None` at the end.
    pub fn read_entry(&mut self) -> Result<Option<(Vec<u8>, u8)>, Errno> {
        loop {
            set_errno(0);
            // SAFETY: the stream is open.
            let ent = unsafe { libc::readdir(self.dir) };
            if ent.is_null() {
                return match errno() {
                    0 => Ok(None),
                    e => Err(e),
                };
            }
            // SAFETY: `d_name` is NUL-terminated within the entry, valid until the next call.
            let name = unsafe { CStr::from_ptr((*ent).d_name.as_ptr()) }.to_bytes();
            if name != b"." && name != b".." {
                // SAFETY: `ent` is valid until the next `readdir`.
                return Ok(Some((name.to_vec(), unsafe { (*ent).d_type })));
            }
        }
    }

    pub fn close(&mut self) {
        if !self.dir.is_null() {
            // SAFETY: the stream is open and closed once.
            unsafe { libc::closedir(self.dir) };
            self.dir = core::ptr::null_mut();
        }
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        self.close();
    }
}

/// Directory entries `(name, d_type)`, excluding `.` and `..`, in on-disk order.
pub fn read_dir(path: &CPath) -> Result<DirEntries, Errno> {
    let mut dir = Dir::open(path)?;
    let mut out = Vec::new();
    while let Some(entry) = dir.read_entry()? {
        out.push(entry);
    }
    Ok(out)
}

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

/// The descriptor of standard stream `which` (0 input, 1 output, 2 error).
pub fn standard(which: i64) -> Fd {
    which as Fd
}

/// Whether `fd` is one of the standard output streams the runtime's buffered `print` shares.
pub fn is_output(fd: Fd) -> bool {
    fd == 1 || fd == 2
}

/// Reads at `offset` without moving the file position; `Ok(0)` at end of file.
pub fn pread(fd: Fd, buf: &mut [u8], offset: i64) -> Result<usize, Errno> {
    // SAFETY: the slice is writable for the requested length.
    retry(|| unsafe {
        libc::pread(
            fd,
            buf.as_mut_ptr() as *mut _,
            buf.len(),
            offset as libc::off_t,
        )
    })
    .map(|n| n as usize)
}

/// Writes at `offset` without moving the file position.
pub fn pwrite(fd: Fd, buf: &[u8], offset: i64) -> Result<usize, Errno> {
    // SAFETY: the slice is readable for the requested length.
    retry(|| unsafe {
        libc::pwrite(
            fd,
            buf.as_ptr() as *const _,
            buf.len(),
            offset as libc::off_t,
        )
    })
    .map(|n| n as usize)
}

/// `lseek` with `origin` 0 (start), 1 (current) or 2 (end); returns the new position.
pub fn seek(fd: Fd, offset: i64, origin: i64) -> Result<i64, Errno> {
    let whence = [libc::SEEK_SET, libc::SEEK_CUR, libc::SEEK_END][origin as usize];
    // SAFETY: plain system call on an open descriptor.
    let at = unsafe { libc::lseek(fd, offset as libc::off_t, whence) };
    if at < 0 { Err(errno()) } else { Ok(at as i64) }
}

pub fn ftruncate(fd: Fd, size: i64) -> Result<(), Errno> {
    // SAFETY: plain system call on an open descriptor.
    if unsafe { libc::ftruncate(fd, size as libc::off_t) } != 0 {
        return Err(errno());
    }
    Ok(())
}

pub fn fsync(fd: Fd) -> Result<(), Errno> {
    // SAFETY: plain system call on an open descriptor.
    if unsafe { libc::fsync(fd) } != 0 {
        return Err(errno());
    }
    Ok(())
}

pub fn fdatasync(fd: Fd) -> Result<(), Errno> {
    #[cfg(target_os = "linux")]
    // SAFETY: plain system call on an open descriptor.
    let r = unsafe { libc::fdatasync(fd) };
    #[cfg(not(target_os = "linux"))]
    // SAFETY: plain system call on an open descriptor.
    let r = unsafe { libc::fsync(fd) };
    if r != 0 {
        return Err(errno());
    }
    Ok(())
}

pub fn fchmod(fd: Fd, mode: u32) -> Result<(), Errno> {
    // SAFETY: plain system call on an open descriptor.
    if unsafe { libc::fchmod(fd, mode as libc::mode_t) } != 0 {
        return Err(errno());
    }
    Ok(())
}

/// `-1` leaves an id unchanged.
pub fn fchown(fd: Fd, uid: i64, gid: i64) -> Result<(), Errno> {
    // SAFETY: plain system call on an open descriptor.
    if unsafe { libc::fchown(fd, uid as libc::uid_t, gid as libc::gid_t) } != 0 {
        return Err(errno());
    }
    Ok(())
}

pub fn futimens(fd: Fd, atime: (i64, i64), mtime: (i64, i64)) -> Result<(), Errno> {
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
    // SAFETY: `times` holds two timespecs.
    if unsafe { libc::futimens(fd, times.as_ptr()) } != 0 {
        return Err(errno());
    }
    Ok(())
}

/// Moves the position back by `by` bytes (returning read-ahead to the file).
pub fn rewind_by(fd: Fd, by: usize) {
    // SAFETY: plain system call on an open descriptor.
    unsafe { libc::lseek(fd, -(by as libc::off_t), libc::SEEK_CUR) };
}

/// Blocks up to `ms` milliseconds until `fd` is ready; `true` when ready, hung up or failed (the
/// next read or write reports the details).
pub fn wait_ready(fd: Fd, interest: Interest, ms: i32) -> bool {
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

pub fn sleep_ms(ms: i32) {
    // SAFETY: polling no descriptors just sleeps.
    unsafe { libc::poll(core::ptr::null_mut(), 0, ms) };
}

/// Whether reads of a descriptor with this `fstat` result may block indefinitely.
pub fn is_pollable(st: &Stat) -> bool {
    !st.is_regular()
}

/// `os.Remove`: `unlink`, then `rmdir`.
pub fn remove(p: &CPath) -> Result<(), Errno> {
    let e = match unlink(p) {
        Ok(()) => return Ok(()),
        Err(e) => e,
    };
    match rmdir(p) {
        Ok(()) => Ok(()),
        Err(e1) => Err(if e1 != libc::ENOTDIR { e1 } else { e }),
    }
}

/// Linux `FICLONE`: makes `output` share the extents of `input`.
pub fn clone_file(output: Fd, input: Fd) -> Result<(), Errno> {
    #[cfg(target_os = "linux")]
    {
        // SAFETY: both descriptors are open; FICLONE takes the source descriptor.
        let r = unsafe { libc::ioctl(output, 0x4004_9409 as _, input) };
        if r != 0 {
            return Err(errno());
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
            return Err(errno());
        }
        Ok(())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (path, mode);
        Err(libc::ENOTSUP)
    }
}

/// The directory for temporary files: `$TMPDIR`, else `/tmp`.
pub fn temp_dir() -> Vec<u8> {
    match env(c"TMPDIR") {
        Some(d) if !d.is_empty() => d,
        _ => b"/tmp".to_vec(),
    }
}

/// Removes a directory tree without following links, descending through directory descriptors so
/// a concurrent rename cannot redirect the removal. `display` names the root in failures.
pub fn remove_tree(path: &[u8]) -> Result<(), (Errno, &'static str, Vec<u8>)> {
    let mut full = path.to_vec();
    full.push(0);
    let c =
        CStr::from_bytes_with_nul(&full).map_err(|_| (libc::EINVAL, "remove", path.to_vec()))?;
    remove_tree_at(libc::AT_FDCWD, c, path)
}

fn remove_tree_at(
    dirfd: c_int,
    name: &CStr,
    display: &[u8],
) -> Result<(), (Errno, &'static str, Vec<u8>)> {
    // SAFETY: `name` is NUL-terminated; the directory is opened without following symlinks.
    let fd = unsafe {
        libc::openat(
            dirfd,
            name.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        return Err((errno(), "openat", display.to_vec()));
    }
    // SAFETY: `fd` is an open directory descriptor and is handed to `fdopendir`.
    let dir = unsafe { libc::fdopendir(fd) };
    if dir.is_null() {
        let e = errno();
        let _ = close(fd);
        return Err((e, "fdopendir", display.to_vec()));
    }
    let mut names: Vec<(Vec<u8>, bool)> = Vec::new();
    loop {
        // SAFETY: `dir` is an open stream.
        let ent = unsafe { libc::readdir(dir) };
        if ent.is_null() {
            break;
        }
        // SAFETY: `d_name` is NUL-terminated within the entry.
        let n = unsafe { CStr::from_ptr((*ent).d_name.as_ptr()) }.to_bytes();
        if n == b"." || n == b".." {
            continue;
        }
        // SAFETY: `ent` is valid until the next `readdir`.
        names.push((n.to_vec(), unsafe { (*ent).d_type } == libc::DT_DIR));
    }
    let mut result = Ok(());
    for (n, is_dir) in names {
        let mut child = display.to_vec();
        child.push(b'/');
        child.extend_from_slice(&n);
        let mut cname = n.clone();
        cname.push(0);
        let c = CStr::from_bytes_with_nul(&cname).expect("names contain no NUL");
        // `d_type` can be unknown; the unlink attempt below falls back to a directory removal.
        let r = if is_dir {
            remove_tree_at(fd, c, &child)
        } else {
            // SAFETY: `c` is NUL-terminated and `fd` is the open directory.
            if unsafe { libc::unlinkat(fd, c.as_ptr(), 0) } == 0 {
                Ok(())
            } else if matches!(errno(), libc::EISDIR | libc::EPERM) {
                remove_tree_at(fd, c, &child)
            } else {
                Err((errno(), "unlinkat", child))
            }
        };
        if r.is_err() {
            result = r;
            break;
        }
    }
    // SAFETY: closes the stream and its descriptor once.
    unsafe { libc::closedir(dir) };
    result?;
    // SAFETY: `name` is NUL-terminated.
    if unsafe { libc::unlinkat(dirfd, name.as_ptr(), libc::AT_REMOVEDIR) } != 0 {
        return Err((errno(), "unlinkat", display.to_vec()));
    }
    Ok(())
}

/// A pipe `(read, write)` for tests.
#[cfg(test)]
pub fn pipe() -> (Fd, Fd) {
    let mut fds = [0 as Fd; 2];
    // SAFETY: `fds` has room for two descriptors.
    assert_eq!(unsafe { libc::pipe(fds.as_mut_ptr()) }, 0);
    (fds[0], fds[1])
}

/// The status an `errno` maps to (`classifyOS`).
pub fn classify(e: Errno) -> u8 {
    match e {
        libc::ENOSYS | libc::ENOTSUP => ms_rt_abi::STATUS_UNSUPPORTED,
        libc::ENOENT => ms_rt_abi::STATUS_NOT_FOUND,
        libc::ENOTEMPTY => ms_rt_abi::STATUS_NOT_EMPTY,
        libc::EEXIST => ms_rt_abi::STATUS_ALREADY_EXISTS,
        libc::EISDIR | libc::ENOTDIR | libc::EBADF | libc::EINVAL => {
            ms_rt_abi::STATUS_INVALID_INPUT
        }
        libc::EACCES | libc::EPERM => ms_rt_abi::STATUS_PERMISSION_DENIED,
        _ => ms_rt_abi::STATUS_FAILED,
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
