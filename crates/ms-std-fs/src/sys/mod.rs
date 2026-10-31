//! Host calls the filesystem natives need, built on `std::fs`, `std::io`, `std::env` and
//! `std::path`. Paths are byte strings (UTF-8 on Windows). Failures are reported as the host's
//! native error code (`errno` or a Win32 error), which `classify` and `describe` interpret.
//!
//! A file "descriptor" is the raw OS handle (`c_int` on Unix, `HANDLE` on Windows), operated on
//! through a `File` that is never dropped; closing drops an owned one. `unix.rs` and `windows.rs`
//! hold only what `std` cannot do.
use alloc::borrow::Cow;
use alloc::string::String;
use alloc::vec::Vec;
use std::ffi::{CStr, OsStr};
use std::fs::{self, File, OpenOptions};
use std::hash::{BuildHasher, RandomState};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::mem::ManuallyDrop;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[cfg(unix)]
mod unix;
#[cfg(windows)]
mod windows;

#[cfg(all(unix, test))]
pub use unix::wait_ready;
#[cfg(unix)]
pub use unix::{access, chmod_link, clone_file, pipe_cloexec, set_errno, statfs};
#[cfg(windows)]
pub use windows::{is_output, standard, statfs, wait_ready};

pub type Errno = i32;

/// Host file descriptors.
#[cfg(unix)]
pub type Fd = std::os::fd::RawFd;
/// Host file handles.
#[cfg(windows)]
pub type Fd = isize;

/// The value of a descriptor that is not open.
pub const INVALID_FD: Fd = -1;

/// Error codes this layer reports itself. They are real OS codes, so `classify` and `describe`
/// treat them like any other.
#[cfg(unix)]
mod codes {
    use super::Errno;
    pub const EINVAL: Errno = libc::EINVAL;
    pub const EEXIST: Errno = libc::EEXIST;
    pub const EIO: Errno = libc::EIO;
    pub const EBADF: Errno = libc::EBADF;
    pub const UNSUPPORTED: Errno = libc::ENOTSUP;
}
#[cfg(windows)]
mod codes {
    use super::Errno;
    /// `ERROR_INVALID_PARAMETER`
    pub const EINVAL: Errno = 87;
    /// `ERROR_FILE_EXISTS`
    pub const EEXIST: Errno = 80;
    /// `ERROR_IO_DEVICE`
    pub const EIO: Errno = 1117;
    /// `ERROR_INVALID_HANDLE`
    pub const EBADF: Errno = 6;
    /// `ERROR_NOT_SUPPORTED`
    pub const UNSUPPORTED: Errno = 50;
}
pub use codes::{EEXIST, EINVAL, EIO, UNSUPPORTED};

/// The `O_*` open flags: the host's own on Unix, Go's values on Windows.
#[cfg(unix)]
pub use libc::{O_APPEND, O_CREAT, O_EXCL, O_RDONLY, O_RDWR, O_TRUNC, O_WRONLY};
#[cfg(windows)]
pub const O_RDONLY: i32 = 0x0;
#[cfg(windows)]
pub const O_WRONLY: i32 = 0x1;
#[cfg(windows)]
pub const O_RDWR: i32 = 0x2;
#[cfg(windows)]
pub const O_CREAT: i32 = 0x40;
#[cfg(windows)]
pub const O_EXCL: i32 = 0x80;
#[cfg(windows)]
pub const O_TRUNC: i32 = 0x200;
#[cfg(windows)]
pub const O_APPEND: i32 = 0x400;
#[cfg(windows)]
pub const O_SYNC: i32 = 0x1000;

pub const S_IFMT: u32 = 0o170000;
pub const S_IFSOCK: u32 = 0o140000;
pub const S_IFLNK: u32 = 0o120000;
pub const S_IFREG: u32 = 0o100000;
pub const S_IFBLK: u32 = 0o060000;
pub const S_IFDIR: u32 = 0o040000;
pub const S_IFCHR: u32 = 0o020000;
pub const S_IFIFO: u32 = 0o010000;

/// The entry kinds `read_dir` reports (the Unix `d_type` values).
pub const DT_UNKNOWN: u8 = 0;
pub const DT_DIR: u8 = 4;
pub const DT_REG: u8 = 8;
pub const DT_LNK: u8 = 10;

/// What `stat` reports, in Unix terms: `mode` carries the `S_IF*` file type and permission bits.
/// Times are `(seconds, nanoseconds)`. Fields a host cannot report are zero.
#[derive(Clone, Copy, Debug, Default)]
pub struct Stat {
    pub mode: u32,
    pub size: i64,
    pub modified: (i64, i64),
    pub accessed: (i64, i64),
    pub changed: (i64, i64),
    /// The creation time, when the host and filesystem report one.
    pub created: Option<(i64, i64)>,
    pub block_size: u64,
    pub blocks: u64,
    pub rdev: u64,
    pub device: u64,
    pub inode: u64,
    pub links: u64,
    pub uid: u64,
    pub gid: u64,
}

impl Stat {
    pub fn kind(&self) -> u32 {
        self.mode & S_IFMT
    }

    pub fn is_dir(&self) -> bool {
        self.kind() == S_IFDIR
    }

    pub fn is_link(&self) -> bool {
        self.kind() == S_IFLNK
    }

    pub fn is_regular(&self) -> bool {
        self.kind() == S_IFREG
    }

    /// Whether this is a named pipe, whose open and reads wait for the other end.
    #[cfg(unix)]
    pub fn is_fifo(&self) -> bool {
        self.kind() == libc::S_IFIFO as u32
    }

    /// Whether both describe the same file (`os.SameFile`).
    pub fn same_file(&self, other: &Stat) -> bool {
        self.device == other.device && self.inode == other.inode
    }
}

pub fn is_dir(st: &Stat) -> bool {
    st.is_dir()
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

/// What a wait is for.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Interest {
    Read,
    Write,
}

/// Directory entries `(name, kind)` where `kind` is one of the `DT_*` values.
pub type DirEntries = Vec<(Vec<u8>, u8)>;

// ---------------------------------------------------------------------------
// Paths, errors and conversions
// ---------------------------------------------------------------------------

/// `path` as a `Path`. Windows paths are UTF-8; anything else is replaced.
pub fn path_of(path: &[u8]) -> Cow<'_, Path> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        Cow::Borrowed(Path::new(OsStr::from_bytes(path)))
    }
    #[cfg(windows)]
    {
        match String::from_utf8_lossy(path) {
            Cow::Borrowed(s) => Cow::Borrowed(Path::new(s)),
            Cow::Owned(s) => Cow::Owned(PathBuf::from(s)),
        }
    }
}

/// The bytes of a host string (UTF-8 on Windows, lossily).
pub fn os_bytes(s: &OsStr) -> Vec<u8> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        s.as_bytes().to_vec()
    }
    #[cfg(windows)]
    {
        s.to_string_lossy().into_owned().into_bytes()
    }
}

/// A validated path: `None` when it is empty, contains a NUL or (on Windows) is not UTF-8.
pub struct CPath {
    path: PathBuf,
    /// The bytes plus a trailing NUL.
    raw: Vec<u8>,
}

impl CPath {
    pub fn new(path: &[u8]) -> Option<CPath> {
        if path.is_empty() || path.contains(&0) {
            return None;
        }
        #[cfg(windows)]
        core::str::from_utf8(path).ok()?;
        let mut raw = Vec::with_capacity(path.len() + 1);
        raw.extend_from_slice(path);
        raw.push(0);
        Some(CPath {
            path: path_of(path).into_owned(),
            raw,
        })
    }

    /// A NUL-terminated pointer for the libc calls that remain.
    #[cfg(unix)]
    pub fn as_ptr(&self) -> *const core::ffi::c_char {
        self.raw.as_ptr().cast()
    }

    pub fn bytes(&self) -> &[u8] {
        &self.raw[..self.raw.len() - 1]
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

/// The OS error code of `e`. Errors `std` raises itself (no OS code) map to a close code.
pub fn code(e: &io::Error) -> Errno {
    if let Some(c) = e.raw_os_error() {
        return c;
    }
    match e.kind() {
        io::ErrorKind::InvalidInput => EINVAL,
        io::ErrorKind::Unsupported => UNSUPPORTED,
        _ => EIO,
    }
}

/// The calling thread's last OS error code.
pub fn errno() -> Errno {
    io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

fn kind(e: Errno) -> io::ErrorKind {
    io::Error::from_raw_os_error(e).kind()
}

/// `true` when `e` says the path does not exist.
pub fn is_not_found(e: Errno) -> bool {
    kind(e) == io::ErrorKind::NotFound
}

/// `true` when `e` says the path already exists.
pub fn is_exists(e: Errno) -> bool {
    kind(e) == io::ErrorKind::AlreadyExists
}

/// `true` when `e` says a non-blocking descriptor has nothing to transfer yet.
pub fn would_block(e: Errno) -> bool {
    kind(e) == io::ErrorKind::WouldBlock
}

/// `true` when `e` says a path component is not a directory.
fn is_not_dir(e: Errno) -> bool {
    // `ERROR_DIRECTORY`
    kind(e) == io::ErrorKind::NotADirectory || (cfg!(windows) && e == 267)
}

/// `true` when the access mode of `flags` forbids reading.
pub fn write_only(flags: i32) -> bool {
    flags & (O_WRONLY | O_RDWR) == O_WRONLY
}

/// `true` when the access mode of `flags` forbids writing.
pub fn read_only(flags: i32) -> bool {
    flags & (O_WRONLY | O_RDWR) == O_RDONLY
}

/// The status an error code maps to (`classifyOS`), by the kind `std` gives it.
pub fn classify(e: Errno) -> u8 {
    use io::ErrorKind::*;
    // `std` leaves Windows `ERROR_NOT_SUPPORTED` uncategorized.
    if e == UNSUPPORTED {
        return ms_rt_abi::STATUS_UNSUPPORTED;
    }
    match kind(e) {
        Unsupported => ms_rt_abi::STATUS_UNSUPPORTED,
        NotFound => ms_rt_abi::STATUS_NOT_FOUND,
        DirectoryNotEmpty => ms_rt_abi::STATUS_NOT_EMPTY,
        AlreadyExists => ms_rt_abi::STATUS_ALREADY_EXISTS,
        IsADirectory | NotADirectory | InvalidInput => ms_rt_abi::STATUS_INVALID_INPUT,
        PermissionDenied => ms_rt_abi::STATUS_PERMISSION_DENIED,
        _ => ms_rt_abi::STATUS_FAILED,
    }
}

/// The text for an error code, as `<kind>: <detail>`: the kind is `std`'s stable name for the
/// class of failure (the same on every host, so a script can match it); the detail is a fixed
/// wording on Unix and `std`'s message otherwise (without its trailing " (os error N)").
pub fn describe(e: Errno) -> String {
    let err = io::Error::from_raw_os_error(e);
    #[cfg(unix)]
    if let Some(text) = unix::errno_text(e) {
        return format!("{}: {text}", err.kind());
    }
    let mut text = err.to_string();
    if let Some(i) = text.rfind(" (os error ") {
        text.truncate(i);
    }
    format!("{}: {text}", err.kind())
}

fn unix_pair(t: SystemTime) -> (i64, i64) {
    match t.duration_since(UNIX_EPOCH) {
        Ok(d) => (d.as_secs() as i64, i64::from(d.subsec_nanos())),
        Err(e) => {
            let (secs, nanos) = (e.duration().as_secs() as i64, e.duration().subsec_nanos());
            if nanos == 0 {
                (-secs, 0)
            } else {
                (-secs - 1, 1_000_000_000 - i64::from(nanos))
            }
        }
    }
}

fn system_time((secs, nanos): (i64, i64)) -> io::Result<SystemTime> {
    let base = if secs >= 0 {
        UNIX_EPOCH.checked_add(Duration::from_secs(secs as u64))
    } else {
        UNIX_EPOCH.checked_sub(Duration::from_secs(secs.unsigned_abs()))
    };
    base.and_then(|t| t.checked_add(Duration::from_nanos(nanos.clamp(0, 999_999_999) as u64)))
        .ok_or_else(|| io::ErrorKind::InvalidInput.into())
}

// ---------------------------------------------------------------------------
// Descriptors
// ---------------------------------------------------------------------------

fn is_invalid(fd: Fd) -> bool {
    // A null handle is as unusable as `INVALID_HANDLE_VALUE`.
    fd == INVALID_FD || (cfg!(windows) && fd == 0)
}

/// A `File` over a descriptor the caller keeps owning.
///
/// # Safety
/// `fd` must be an open descriptor or handle for as long as the result is used. The result is
/// never dropped, so it never closes `fd`.
unsafe fn borrow(fd: Fd) -> ManuallyDrop<File> {
    // SAFETY: forwarded from the caller.
    #[cfg(unix)]
    let file = unsafe { <File as std::os::fd::FromRawFd>::from_raw_fd(fd) };
    // SAFETY: forwarded from the caller.
    #[cfg(windows)]
    let file = unsafe {
        <File as std::os::windows::io::FromRawHandle>::from_raw_handle(
            fd as std::os::windows::io::RawHandle,
        )
    };
    ManuallyDrop::new(file)
}

/// Runs `f` on the file behind `fd` without taking ownership, retrying `Interrupted`.
fn with<T>(fd: Fd, mut f: impl FnMut(&File) -> io::Result<T>) -> Result<T, Errno> {
    if is_invalid(fd) {
        return Err(codes::EBADF);
    }
    // SAFETY: callers pass a descriptor they hold open for the call.
    let file = unsafe { borrow(fd) };
    loop {
        match f(&file) {
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            r => return r.map_err(|e| code(&e)),
        }
    }
}

fn into_fd(file: File) -> Fd {
    #[cfg(unix)]
    {
        std::os::fd::IntoRawFd::into_raw_fd(file)
    }
    #[cfg(windows)]
    {
        std::os::windows::io::IntoRawHandle::into_raw_handle(file) as Fd
    }
}

/// Opens `path` with `flags` (the `O_*` values of this module) and permission bits `mode`.
pub fn open(path: &CPath, flags: i32, mode: u32) -> Result<Fd, Errno> {
    #[cfg(unix)]
    let opened = {
        use std::os::unix::fs::OpenOptionsExt;
        let access = flags & libc::O_ACCMODE;
        // The whole word goes through, so creation, truncation and append flags apply as given;
        // `std` supplies the access mode and `O_CLOEXEC`.
        OpenOptions::new()
            .read(access != O_WRONLY)
            .write(access != O_RDONLY)
            .mode(mode)
            .custom_flags(flags)
            .open(path.path())
    };
    #[cfg(windows)]
    let opened = windows::open(path.path(), flags, mode);
    opened.map(into_fd).map_err(|e| code(&e))
}

/// Closes an owned descriptor: dropping the `File` closes it.
pub fn close(fd: Fd) -> Result<(), Errno> {
    if is_invalid(fd) {
        return Err(codes::EBADF);
    }
    // SAFETY: the caller hands over ownership of an open descriptor.
    drop(ManuallyDrop::into_inner(unsafe { borrow(fd) }));
    Ok(())
}

/// A second descriptor over the same open file (`dup` on Unix, `DuplicateHandle` on Windows),
/// closed on its own; the two share the file position.
pub fn duplicate(fd: Fd) -> Result<Fd, Errno> {
    if is_invalid(fd) {
        return Err(codes::EBADF);
    }
    // SAFETY: the caller keeps `fd` open for this call; the borrow is never dropped.
    let file = unsafe { borrow(fd) };
    file.try_clone().map(into_fd).map_err(|e| code(&e))
}

/// The descriptor of standard stream `which` (0 input, 1 output, 2 error).
#[cfg(unix)]
pub fn standard(which: i64) -> Fd {
    which as Fd
}

/// Points standard stream `which` (0 input, 1 output, 2 error) of this process at the null
/// device, so children started afterwards inherit it too.
#[cfg(unix)]
pub fn redirect_standard_to_null(which: i64) -> Result<(), Errno> {
    use std::os::fd::AsRawFd;
    let null = OpenOptions::new()
        .read(true)
        .write(true)
        .open("/dev/null")
        .map_err(|e| code(&e))?;
    // SAFETY: both descriptors are open; `dup2` replaces `which` and `null` closes on drop.
    if unsafe { libc::dup2(null.as_raw_fd(), which as Fd) } < 0 {
        return Err(code(&io::Error::last_os_error()));
    }
    Ok(())
}

/// Points standard stream `which` of this process at the null device (`NUL`).
#[cfg(windows)]
pub fn redirect_standard_to_null(which: i64) -> Result<(), Errno> {
    windows::redirect_standard_to_null(which).map_err(|e| code(&e))
}

/// Whether `fd` is one of the standard output streams the runtime's buffered `print` shares.
#[cfg(unix)]
pub fn is_output(fd: Fd) -> bool {
    fd == 1 || fd == 2
}

pub fn read(fd: Fd, buf: &mut [u8]) -> Result<usize, Errno> {
    #[cfg(windows)]
    if let Some(r) = windows::read_standard(fd, buf) {
        return r.map_err(|e| code(&e));
    }
    with(fd, |mut f| f.read(&mut *buf))
}

pub fn write(fd: Fd, buf: &[u8]) -> Result<usize, Errno> {
    #[cfg(windows)]
    if let Some(r) = windows::write_standard(fd, buf) {
        return r.map_err(|e| code(&e));
    }
    with(fd, |mut f| f.write(buf))
}

/// Reads at `offset` without moving the file position; `Ok(0)` at end of file.
pub fn pread(fd: Fd, buf: &mut [u8], offset: i64) -> Result<usize, Errno> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::FileExt;
        with(fd, |f| f.read_at(&mut *buf, offset as u64))
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::FileExt;
        positioned(fd, |f| f.seek_read(&mut *buf, offset as u64))
    }
}

/// Writes at `offset` without moving the file position.
pub fn pwrite(fd: Fd, buf: &[u8], offset: i64) -> Result<usize, Errno> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::FileExt;
        with(fd, |f| f.write_at(buf, offset as u64))
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::FileExt;
        positioned(fd, |f| f.seek_write(buf, offset as u64))
    }
}

/// Windows moves the file position on a positioned transfer; put it back afterwards.
#[cfg(windows)]
fn positioned(fd: Fd, mut f: impl FnMut(&File) -> io::Result<usize>) -> Result<usize, Errno> {
    with(fd, |file| {
        let mut handle = file;
        let saved = handle.stream_position()?;
        let r = f(file);
        handle.seek(SeekFrom::Start(saved))?;
        r
    })
}

/// Seeks from `origin` 0 (start), 1 (current) or 2 (end); returns the new position.
pub fn seek(fd: Fd, offset: i64, origin: i64) -> Result<i64, Errno> {
    let to = match origin {
        0 if offset >= 0 => SeekFrom::Start(offset as u64),
        1 => SeekFrom::Current(offset),
        2 => SeekFrom::End(offset),
        _ => return Err(EINVAL),
    };
    with(fd, |mut f| f.seek(to)).map(|at| at as i64)
}

/// Moves the position back by `by` bytes (returning read-ahead to the file).
pub fn rewind_by(fd: Fd, by: usize) {
    let _ = seek(fd, -(by as i64), 1);
}

pub fn ftruncate(fd: Fd, size: i64) -> Result<(), Errno> {
    with(fd, |f| f.set_len(size as u64))
}

pub fn fsync(fd: Fd) -> Result<(), Errno> {
    with(fd, File::sync_all)
}

pub fn fdatasync(fd: Fd) -> Result<(), Errno> {
    with(fd, File::sync_data)
}

/// Sets the permission bits (Windows: the read-only attribute from the owner write bit).
pub fn fchmod(fd: Fd, mode: u32) -> Result<(), Errno> {
    with(fd, |f| {
        f.set_permissions(permissions(|| Ok(f.metadata()?.permissions()), mode)?)
    })
}

/// The permissions for `mode`: its bits on Unix; on Windows `current` with the read-only
/// attribute set from the owner write bit (`current` is only read there).
fn permissions(
    current: impl FnOnce() -> io::Result<fs::Permissions>,
    mode: u32,
) -> io::Result<fs::Permissions> {
    #[cfg(unix)]
    {
        let _ = current;
        Ok(std::os::unix::fs::PermissionsExt::from_mode(mode))
    }
    #[cfg(windows)]
    {
        let mut p = current()?;
        p.set_readonly(mode & 0o200 == 0);
        Ok(p)
    }
}

/// `-1` leaves an id unchanged. Ownership does not exist on Windows.
pub fn fchown(fd: Fd, uid: i64, gid: i64) -> Result<(), Errno> {
    #[cfg(unix)]
    {
        with(fd, |f| std::os::unix::fs::fchown(f, id(uid), id(gid)))
    }
    #[cfg(windows)]
    {
        let _ = (fd, uid, gid);
        Err(UNSUPPORTED)
    }
}

#[cfg(unix)]
fn id(v: i64) -> Option<u32> {
    (v >= 0).then_some(v as u32)
}

pub fn futimens(fd: Fd, atime: (i64, i64), mtime: (i64, i64)) -> Result<(), Errno> {
    let times = fs::FileTimes::new()
        .set_accessed(system_time(atime).map_err(|e| code(&e))?)
        .set_modified(system_time(mtime).map_err(|e| code(&e))?);
    with(fd, |f| f.set_times(times))
}

/// Whether reads of a descriptor with this `fstat` result may block indefinitely.
pub fn is_pollable(st: &Stat) -> bool {
    !st.is_regular()
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

#[cfg(unix)]
fn stat_of(m: &fs::Metadata) -> Stat {
    use std::os::unix::fs::MetadataExt;
    Stat {
        mode: m.mode(),
        size: m.size() as i64,
        modified: (m.mtime(), m.mtime_nsec()),
        accessed: (m.atime(), m.atime_nsec()),
        changed: (m.ctime(), m.ctime_nsec()),
        created: m.created().ok().map(unix_pair),
        block_size: m.blksize(),
        blocks: m.blocks(),
        rdev: m.rdev(),
        device: m.dev(),
        inode: m.ino(),
        links: m.nlink(),
        uid: u64::from(m.uid()),
        gid: u64::from(m.gid()),
    }
}

/// Switches a descriptor back to blocking mode after an open that could not wait.
#[cfg(unix)]
pub fn clear_nonblocking(fd: Fd) {
    // SAFETY: `fd` is a descriptor the caller owns; fcntl touches no memory.
    unsafe {
        let current = libc::fcntl(fd, libc::F_GETFL);
        libc::fcntl(fd, libc::F_SETFL, current & !libc::O_NONBLOCK);
    }
}

pub fn fstat(fd: Fd) -> Result<Stat, Errno> {
    #[cfg(unix)]
    {
        with(fd, |f| f.metadata().map(|m| stat_of(&m)))
    }
    #[cfg(windows)]
    {
        with(fd, windows::fstat)
    }
}

pub fn stat(path: &CPath, follow: bool) -> Result<Stat, Errno> {
    #[cfg(unix)]
    let st = if follow {
        fs::metadata(path.path())
    } else {
        fs::symlink_metadata(path.path())
    }
    .map(|m| stat_of(&m));
    #[cfg(windows)]
    let st = windows::stat_path(path.path(), follow);
    st.map_err(|e| code(&e))
}

// ---------------------------------------------------------------------------
// Directories and links
// ---------------------------------------------------------------------------

fn done(r: io::Result<()>) -> Result<(), Errno> {
    r.map_err(|e| code(&e))
}

fn dir_builder(mode: u32, recursive: bool) -> fs::DirBuilder {
    let mut b = fs::DirBuilder::new();
    b.recursive(recursive);
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, mode);
    #[cfg(windows)]
    let _ = mode;
    b
}

pub fn mkdir(path: &CPath, mode: u32) -> Result<(), Errno> {
    done(dir_builder(mode, false).create(path.path()))
}

/// Creates `path` and its missing ancestors; an existing directory is not an error.
pub fn mkdir_all(path: &CPath, mode: u32) -> Result<(), Errno> {
    done(dir_builder(mode, true).create(path.path()))
}

pub fn unlink(path: &CPath) -> Result<(), Errno> {
    done(fs::remove_file(path.path()))
}

pub fn rmdir(path: &CPath) -> Result<(), Errno> {
    done(fs::remove_dir(path.path()))
}

/// `os.Remove`: remove as a file, then as a directory.
pub fn remove(p: &CPath) -> Result<(), Errno> {
    let Err(e) = unlink(p) else { return Ok(()) };
    match rmdir(p) {
        Err(e1) if !is_not_dir(e1) => Err(e1),
        Err(_) => Err(e),
        Ok(()) => Ok(()),
    }
}

/// Removes a directory tree without following links.
pub fn remove_tree(path: &CPath) -> Result<(), Errno> {
    done(fs::remove_dir_all(path.path()))
}

pub fn rename(from: &CPath, to: &CPath) -> Result<(), Errno> {
    done(fs::rename(from.path(), to.path()))
}

pub fn link(from: &CPath, to: &CPath) -> Result<(), Errno> {
    done(fs::hard_link(from.path(), to.path()))
}

/// Creates the symbolic link `path` naming `target`.
pub fn symlink(target: &CPath, path: &CPath) -> Result<(), Errno> {
    #[cfg(unix)]
    {
        done(std::os::unix::fs::symlink(target.path(), path.path()))
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::{symlink_dir, symlink_file};
        // Windows wants `\` in the target, and a file link and a directory link are different
        // objects: the target decides (relative to the link's directory when relative). Creating
        // one needs a privilege unless Developer Mode is on.
        let text = String::from_utf8_lossy(target.bytes()).replace('/', "\\");
        let target = Path::new(&text);
        let resolved = path
            .path()
            .parent()
            .map_or_else(|| target.to_path_buf(), |dir| dir.join(target));
        let is_dir = fs::metadata(resolved).is_ok_and(|m| m.is_dir());
        done(if is_dir {
            symlink_dir(target, path.path())
        } else {
            symlink_file(target, path.path())
        })
    }
}

pub fn readlink(path: &CPath) -> Result<Vec<u8>, Errno> {
    fs::read_link(path.path())
        .map(|p| os_bytes(p.as_os_str()))
        .map_err(|e| code(&e))
}

/// `filepath.EvalSymlinks` for a path that exists: `std`'s canonical form (absolute; on Windows
/// with the `\\?\` prefix).
pub fn canonicalize(path: &CPath) -> Result<Vec<u8>, Errno> {
    fs::canonicalize(path.path())
        .map(|p| os_bytes(p.as_os_str()))
        .map_err(|e| code(&e))
}

/// Directory entries `(name, kind)` excluding `.` and `..`, in the host's order.
pub fn read_dir(path: &CPath) -> Result<DirEntries, Errno> {
    let mut dir = Dir::open(path)?;
    let mut out = Vec::new();
    while let Some(entry) = dir.read_entry()? {
        out.push(entry);
    }
    Ok(out)
}

/// An open directory stream.
pub struct Dir {
    entries: Option<fs::ReadDir>,
}

fn entry_kind(entry: &fs::DirEntry) -> u8 {
    match entry.file_type() {
        Ok(t) if t.is_symlink() => DT_LNK,
        Ok(t) if t.is_dir() => DT_DIR,
        Ok(t) if t.is_file() => DT_REG,
        // Devices, pipes and sockets (or no answer): the caller asks `lstat`.
        _ => DT_UNKNOWN,
    }
}

impl Dir {
    pub fn open(path: &CPath) -> Result<Dir, Errno> {
        let entries = fs::read_dir(path.path()).map_err(|e| code(&e))?;
        Ok(Dir {
            entries: Some(entries),
        })
    }

    /// The next entry `(name, kind)`; `None` at the end or once closed.
    pub fn read_entry(&mut self) -> Result<Option<(Vec<u8>, u8)>, Errno> {
        let Some(entries) = self.entries.as_mut() else {
            return Ok(None);
        };
        match entries.next() {
            None => Ok(None),
            Some(Err(e)) => Err(code(&e)),
            Some(Ok(entry)) => Ok(Some((os_bytes(&entry.file_name()), entry_kind(&entry)))),
        }
    }

    pub fn close(&mut self) {
        self.entries = None;
    }
}

// ---------------------------------------------------------------------------
// Attributes
// ---------------------------------------------------------------------------

pub fn chmod(path: &CPath, mode: u32) -> Result<(), Errno> {
    let current = || Ok(fs::metadata(path.path())?.permissions());
    done(permissions(current, mode).and_then(|p| fs::set_permissions(path.path(), p)))
}

/// `chown` (or `lchown` when not following links); `-1` leaves an id unchanged. Ownership does
/// not exist on Windows.
pub fn chown(path: &CPath, uid: i64, gid: i64, follow: bool) -> Result<(), Errno> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::{chown, lchown};
        let (u, g) = (id(uid), id(gid));
        done(if follow {
            chown(path.path(), u, g)
        } else {
            lchown(path.path(), u, g)
        })
    }
    #[cfg(windows)]
    {
        let _ = (path, uid, gid, follow);
        Err(UNSUPPORTED)
    }
}

pub fn truncate(path: &CPath, size: i64) -> Result<(), Errno> {
    let file = OpenOptions::new()
        .write(true)
        .open(path.path())
        .map_err(|e| code(&e))?;
    done(file.set_len(size as u64))
}

/// `hostos.Access`: existence, plus an open for reading or writing when asked.
#[cfg(windows)]
pub fn access(path: &CPath, mode: i32) -> Result<(), Errno> {
    let md = fs::metadata(path.path()).map_err(|e| code(&e))?;
    if mode == 0 || md.is_dir() {
        return Ok(());
    }
    let mut options = OpenOptions::new();
    options.read(true).write(mode & 2 != 0);
    done(options.open(path.path()).map(drop))
}

/// Changing a link's own mode is unsupported on Windows.
#[cfg(windows)]
pub fn chmod_link(_: &CPath, _: u32) -> Result<(), Errno> {
    Err(UNSUPPORTED)
}

/// Block cloning is not supported on Windows (`hostos.CloneFile`).
#[cfg(windows)]
pub fn clone_file(_: Fd, _: Fd) -> Result<(), Errno> {
    Err(UNSUPPORTED)
}

/// `os.Chtimes`: sets the times of the file `path` names, or of the link itself when not
/// following (unsupported on Windows).
pub fn utimens(
    path: &CPath,
    atime: (i64, i64),
    mtime: (i64, i64),
    follow: bool,
) -> Result<(), Errno> {
    if !follow {
        #[cfg(unix)]
        return unix::utimens_nofollow(path, atime, mtime);
        #[cfg(windows)]
        return Err(UNSUPPORTED);
    }
    let times = fs::FileTimes::new()
        .set_accessed(system_time(atime).map_err(|e| code(&e))?)
        .set_modified(system_time(mtime).map_err(|e| code(&e))?);
    done(open_for_times(path.path())?.set_times(times))
}

/// A handle that may have its times set: read-only where that works (directories included), else
/// write-only.
#[cfg(unix)]
fn open_for_times(path: &Path) -> Result<File, Errno> {
    File::open(path)
        .or_else(|_| OpenOptions::new().write(true).open(path))
        .map_err(|e| code(&e))
}

/// A handle with `FILE_WRITE_ATTRIBUTES` access, which also opens directories.
#[cfg(windows)]
fn open_for_times(path: &Path) -> Result<File, Errno> {
    use std::os::windows::fs::OpenOptionsExt;
    const FILE_WRITE_ATTRIBUTES: u32 = 0x100;
    const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x0200_0000;
    OpenOptions::new()
        .access_mode(FILE_WRITE_ATTRIBUTES)
        .custom_flags(FILE_FLAG_BACKUP_SEMANTICS)
        .open(path)
        .map_err(|e| code(&e))
}

// ---------------------------------------------------------------------------
// Process environment
// ---------------------------------------------------------------------------

pub fn getcwd() -> Result<Vec<u8>, Errno> {
    std::env::current_dir()
        .map(|p| os_bytes(p.as_os_str()))
        .map_err(|e| code(&e))
}

/// The directory for temporary files (`$TMPDIR` or `/tmp` on Unix).
pub fn temp_dir() -> Vec<u8> {
    os_bytes(std::env::temp_dir().as_os_str())
}

/// The value of an environment variable.
pub fn env(name: &CStr) -> Option<Vec<u8>> {
    #[cfg(unix)]
    let key = {
        use std::os::unix::ffi::OsStrExt;
        OsStr::from_bytes(name.to_bytes())
    };
    #[cfg(windows)]
    let key = OsStr::new(name.to_str().ok()?);
    std::env::var_os(key).map(|v| os_bytes(&v))
}

pub fn random_u32() -> u32 {
    RandomState::new().hash_one(0u8) as u32
}

#[cfg(test)]
pub fn sleep_ms(ms: i32) {
    std::thread::sleep(Duration::from_millis(ms.max(0) as u64));
}

/// A pipe `(read, write)` for tests.
#[cfg(test)]
pub fn pipe() -> (Fd, Fd) {
    let (r, w) = io::pipe().expect("pipe");
    #[cfg(unix)]
    {
        use std::os::fd::IntoRawFd;
        (r.into_raw_fd(), w.into_raw_fd())
    }
    #[cfg(windows)]
    {
        use std::os::windows::io::IntoRawHandle;
        (r.into_raw_handle() as Fd, w.into_raw_handle() as Fd)
    }
}
