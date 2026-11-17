//! The Windows calls `std` has no equivalent for: file identity and link counts (`std` keeps them
//! unstable), volume sizes, readiness polling of pipes and consoles, the Go-style open flags, and
//! the standard streams, which go through `std::io` so it converts console text to UTF-16.
use super::{
    CPath, EINVAL, Errno, Fd, FsStat, INVALID_FD, O_APPEND, O_CREAT, O_EXCL, O_RDONLY, O_RDWR,
    O_SYNC, O_TRUNC, O_WRONLY, S_IFCHR, S_IFDIR, S_IFIFO, S_IFLNK, S_IFREG, Stat, code, unix_pair,
};
use std::fs::{File, Metadata, OpenOptions};
use std::io::{self, Read, Write};
use std::os::windows::ffi::OsStrExt;
use std::os::windows::fs::OpenOptionsExt;
use std::os::windows::io::{AsRawHandle, IntoRawHandle, RawHandle};
use std::path::{Component, Path};
use windows_sys::Win32::Foundation::{CloseHandle, HANDLE, WAIT_OBJECT_0};
use windows_sys::Win32::Storage::FileSystem::{
    BY_HANDLE_FILE_INFORMATION, FILE_ATTRIBUTE_READONLY, FILE_FLAG_BACKUP_SEMANTICS,
    FILE_FLAG_OPEN_REPARSE_POINT, FILE_FLAG_WRITE_THROUGH, FILE_TYPE_CHAR, FILE_TYPE_DISK,
    FILE_TYPE_PIPE, GetDiskFreeSpaceExW, GetDiskFreeSpaceW, GetFileInformationByHandle,
    GetFileType,
};
use windows_sys::Win32::System::Console::{
    GetConsoleMode, STD_ERROR_HANDLE, STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, SetStdHandle,
};
use windows_sys::Win32::System::IO::CancelIoEx;
use windows_sys::Win32::System::Threading::{
    CreateEventW, INFINITE, SetEvent, WaitForMultipleObjects,
};

/// Opens `path` with Go's Windows `O_*` flag values and permission bits `mode` (only the owner
/// write bit matters: without it a created file is read-only).
pub fn open(path: &Path, flags: i32, mode: u32) -> io::Result<File> {
    let access = flags & (O_WRONLY | O_RDWR);
    let create = flags & O_CREAT != 0;
    let exclusive = create && flags & O_EXCL != 0;
    let truncate = flags & O_TRUNC != 0;
    let mut options = OpenOptions::new();
    options
        .read(access != O_WRONLY)
        .write(access != O_RDONLY || create)
        // `std` cannot combine append with truncation; truncation wins.
        .append(flags & O_APPEND != 0 && !truncate);
    if exclusive {
        options.create_new(true);
    } else if create {
        // `CREATE_ALWAYS` would reset the attributes of an existing file; truncate after opening.
        options.create(true);
    } else if truncate {
        options.truncate(true);
    }
    let mut extra = 0;
    if access == O_RDONLY {
        // A read-only open may name a directory.
        extra |= FILE_FLAG_BACKUP_SEMANTICS;
    }
    if exclusive {
        // Never follow a link when creating exclusively.
        extra |= FILE_FLAG_OPEN_REPARSE_POINT;
    }
    if flags & O_SYNC != 0 {
        extra |= FILE_FLAG_WRITE_THROUGH;
    }
    options.custom_flags(extra);
    if mode & 0o200 == 0 {
        options.attributes(FILE_ATTRIBUTE_READONLY);
    }
    let file = options.open(path)?;
    if create && !exclusive && truncate {
        file.set_len(0)?;
    }
    Ok(file)
}

/// A Unix-style `Stat` from `std`'s metadata: directories are `0777`, other files `0666`, both
/// without the write bits when read-only; links are `S_IFLNK`. Windows keeps no owner, device
/// numbers or change time here.
fn synthesize(m: &Metadata) -> Stat {
    let mut perm = if m.permissions().readonly() {
        0o444
    } else {
        0o666
    };
    let kind = m.file_type();
    let mode = if kind.is_symlink() {
        S_IFLNK
    } else if kind.is_dir() {
        perm |= 0o111;
        S_IFDIR
    } else {
        S_IFREG
    };
    let modified = m.modified().map(unix_pair).unwrap_or_default();
    Stat {
        mode: mode | perm,
        size: m.len() as i64,
        modified,
        accessed: m.accessed().map(unix_pair).unwrap_or(modified),
        changed: modified,
        created: m.created().ok().map(unix_pair),
        ..Stat::default()
    }
}

/// Stats an open disk file: `std`'s metadata plus the volume serial number, file index and link
/// count from `GetFileInformationByHandle`.
fn stat_disk(file: &File) -> io::Result<Stat> {
    let mut st = synthesize(&file.metadata()?);
    // SAFETY: zeroed struct is a valid out buffer.
    let mut info: BY_HANDLE_FILE_INFORMATION = unsafe { std::mem::zeroed() };
    // SAFETY: the handle is open and `info` writable.
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut info) } != 0 {
        st.device = info.dwVolumeSerialNumber as u64;
        st.inode = (info.nFileIndexHigh as u64) << 32 | info.nFileIndexLow as u64;
        st.links = info.nNumberOfLinks as u64;
    }
    Ok(st)
}

/// `stat` or `lstat` of `path`, through a handle opened for attribute queries only.
pub fn stat_path(path: &Path, follow: bool) -> io::Result<Stat> {
    let mut flags = FILE_FLAG_BACKUP_SEMANTICS;
    if !follow {
        flags |= FILE_FLAG_OPEN_REPARSE_POINT;
    }
    let file = OpenOptions::new()
        .access_mode(0)
        .custom_flags(flags)
        .open(path)?;
    stat_disk(&file)
}

/// `fstat`: consoles and pipes have no file information and report their type only.
pub fn fstat(file: &File) -> io::Result<Stat> {
    // SAFETY: plain query on an open handle.
    match unsafe { GetFileType(file.as_raw_handle()) } {
        FILE_TYPE_CHAR => Ok(Stat {
            mode: S_IFCHR | 0o666,
            ..Stat::default()
        }),
        FILE_TYPE_PIPE => Ok(Stat {
            mode: S_IFIFO | 0o666,
            ..Stat::default()
        }),
        FILE_TYPE_DISK => stat_disk(file),
        _ => Err(io::Error::last_os_error()),
    }
}

/// `hostos.StatFS`: sizes of the volume holding `path`.
pub fn statfs(path: &CPath) -> Result<FsStat, Errno> {
    // The volume call accepts a missing path, so check the path itself exists first.
    std::fs::metadata(path.path()).map_err(|e| code(&e))?;
    let full = std::path::absolute(path.path()).map_err(|e| code(&e))?;
    let Some(Component::Prefix(prefix)) = full.components().next() else {
        return Err(EINVAL);
    };
    let mut root: Vec<u16> = prefix.as_os_str().encode_wide().collect();
    root.extend([u16::from(b'\\'), 0]);
    let (mut sectors, mut sector_bytes, mut free, mut total) = (0u32, 0u32, 0u32, 0u32);
    // SAFETY: `root` is NUL-terminated and the outputs are writable.
    let ok = unsafe {
        GetDiskFreeSpaceW(
            root.as_ptr(),
            &mut sectors,
            &mut sector_bytes,
            &mut free,
            &mut total,
        )
    };
    if ok == 0 {
        return Err(super::errno());
    }
    let (mut available_bytes, mut total_bytes, mut free_bytes) = (0u64, 0u64, 0u64);
    // SAFETY: as above.
    let ok = unsafe {
        GetDiskFreeSpaceExW(
            root.as_ptr(),
            &mut available_bytes,
            &mut total_bytes,
            &mut free_bytes,
        )
    };
    if ok == 0 {
        return Err(super::errno());
    }
    let block = sectors as u64 * sector_bytes as u64;
    if block == 0 {
        return Err(EINVAL);
    }
    Ok(FsStat {
        kind: 0,
        block_size: block as i64,
        blocks: (total_bytes / block) as i64,
        blocks_free: (free_bytes / block) as i64,
        blocks_available: (available_bytes / block) as i64,
        files: 0,
        files_free: 0,
    })
}

/// Points standard stream `which` (0 input, 1 output, 2 error) at `NUL`; the handle stays open
/// for the life of the process, as the standard handle it now is.
pub fn redirect_standard_to_null(which: i64) -> io::Result<()> {
    let slot = match which {
        0 => STD_INPUT_HANDLE,
        1 => STD_OUTPUT_HANDLE,
        _ => STD_ERROR_HANDLE,
    };
    let null = OpenOptions::new().read(true).write(true).open("NUL")?;
    let handle = null.into_raw_handle();
    // SAFETY: `handle` is an open handle this process now owns for good.
    if unsafe { SetStdHandle(slot, handle) } == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// The handle of standard stream `which` (0 input, 1 output, 2 error).
fn standard(which: i64) -> Fd {
    let handle: RawHandle = match which {
        0 => io::stdin().as_raw_handle(),
        1 => io::stdout().as_raw_handle(),
        _ => io::stderr().as_raw_handle(),
    };
    handle as Fd
}

fn is_standard(fd: Fd, which: i64) -> bool {
    fd != 0 && fd != INVALID_FD && fd == standard(which)
}

/// Whether `fd` is one of the standard output streams the runtime's buffered `print` shares.
pub fn is_output(fd: Fd) -> bool {
    is_standard(fd, 1) || is_standard(fd, 2)
}

/// Reads standard input through `std::io::Stdin`; `None` when `fd` is another handle.
pub fn read_standard(fd: Fd, buf: &mut [u8]) -> Option<io::Result<usize>> {
    is_standard(fd, 0).then(|| io::stdin().lock().read(buf))
}

/// Writes standard output or error through `std::io` and flushes; `None` when `fd` is another
/// handle.
pub fn write_standard(fd: Fd, buf: &[u8]) -> Option<io::Result<usize>> {
    if is_standard(fd, 1) {
        let mut out = io::stdout().lock();
        return Some(out.write(buf).and_then(|n| out.flush().map(|()| n)));
    }
    if is_standard(fd, 2) {
        let mut err = io::stderr().lock();
        return Some(err.write(buf).and_then(|n| err.flush().map(|()| n)));
    }
    None
}

fn is_console(handle: RawHandle) -> bool {
    let mut mode = 0;
    // SAFETY: `mode` is writable.
    unsafe { GetConsoleMode(handle, &mut mode) != 0 }
}

/// What a handle that cannot be polled blocks on.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Source {
    /// A pipe: only a read waits for data, and it cannot be waited on without consuming.
    Pipe,
    /// A console: its input handle is signalled while input records are queued.
    Console,
    /// Anything else never blocks a read.
    Other,
}

/// How `fd` blocks.
pub fn source(fd: Fd) -> Source {
    let handle = fd as RawHandle;
    // SAFETY: plain query.
    match unsafe { GetFileType(handle) } {
        FILE_TYPE_PIPE => Source::Pipe,
        FILE_TYPE_CHAR if is_console(handle) => Source::Console,
        _ => Source::Other,
    }
}

/// A manual-reset event that ends a console wait from another thread.
pub struct Stop(HANDLE);

// SAFETY: an event handle may be signalled and waited on from any thread.
unsafe impl Send for Stop {}
// SAFETY: as above.
unsafe impl Sync for Stop {}

impl Stop {
    pub fn new() -> io::Result<Stop> {
        // SAFETY: no security attributes and no name.
        let event = unsafe { CreateEventW(std::ptr::null(), 1, 0, std::ptr::null()) };
        if event.is_null() {
            return Err(io::Error::last_os_error());
        }
        Ok(Stop(event))
    }

    /// Ends the wait that watches this event, now or whenever it starts.
    pub fn signal(&self) {
        // SAFETY: the event is open until `drop`.
        unsafe { SetEvent(self.0) };
    }
}

impl Drop for Stop {
    fn drop(&mut self) {
        // SAFETY: the event is open and owned here.
        unsafe { CloseHandle(self.0) };
    }
}

/// Blocks until the console input `fd` has input or `stop` is signalled: `true` when it has
/// input (or failed, which the next read reports), `false` when stopped.
pub fn wait_console(fd: Fd, stop: &Stop) -> bool {
    let handles = [fd as HANDLE, stop.0];
    // SAFETY: two open handles; waits for either with no timeout.
    unsafe { WaitForMultipleObjects(2, handles.as_ptr(), 0, INFINITE) == WAIT_OBJECT_0 }
}

/// Fails the blocking read another thread has pending on `fd`, so that thread returns.
pub fn cancel_io(fd: Fd) {
    // SAFETY: cancels every request on an open handle; nothing else uses it meanwhile.
    unsafe { CancelIoEx(fd as HANDLE, std::ptr::null()) };
}
