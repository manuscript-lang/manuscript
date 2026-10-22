//! The Windows calls `std` has no equivalent for: file identity and link counts (`std` keeps them
//! unstable), volume sizes, readiness polling of pipes and consoles, the Go-style open flags, and
//! the standard streams, which go through `std::io` so it converts console text to UTF-16.
use super::{
    CPath, EINVAL, Errno, Fd, FsStat, INVALID_FD, Interest, O_APPEND, O_CREAT, O_EXCL, O_RDONLY,
    O_RDWR, O_SYNC, O_TRUNC, O_WRONLY, S_IFCHR, S_IFDIR, S_IFIFO, S_IFLNK, S_IFREG, Stat, code,
    unix_pair,
};
use std::fs::{File, Metadata, OpenOptions};
use std::io::{self, Read, Write};
use std::os::windows::ffi::OsStrExt;
use std::os::windows::fs::OpenOptionsExt;
use std::os::windows::io::{AsRawHandle, RawHandle};
use std::path::{Component, Path};
use std::time::Duration;
use windows_sys::Win32::Foundation::WAIT_OBJECT_0;
use windows_sys::Win32::Storage::FileSystem::{
    BY_HANDLE_FILE_INFORMATION, FILE_ATTRIBUTE_READONLY, FILE_FLAG_BACKUP_SEMANTICS,
    FILE_FLAG_OPEN_REPARSE_POINT, FILE_FLAG_WRITE_THROUGH, FILE_TYPE_CHAR, FILE_TYPE_DISK,
    FILE_TYPE_PIPE, GetDiskFreeSpaceExW, GetDiskFreeSpaceW, GetFileInformationByHandle,
    GetFileType,
};
use windows_sys::Win32::System::Console::GetConsoleMode;
use windows_sys::Win32::System::Pipes::PeekNamedPipe;
use windows_sys::Win32::System::Threading::WaitForSingleObject;

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

/// The handle of standard stream `which` (0 input, 1 output, 2 error).
pub fn standard(which: i64) -> Fd {
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

/// Lets other tasks run for 2 ms between checks of a handle that cannot be polled.
fn pause_2ms() {
    #[cfg(not(test))]
    ms_std_rt::task_sleep(2_000_000);
    // Tests run on many threads, which the runtime's scheduler does not support.
    #[cfg(test)]
    std::thread::sleep(Duration::from_millis(2));
}

/// Blocks up to `ms` milliseconds until `fd` is ready; `true` when ready, hung up or failed (the
/// next read or write reports the details). Only pipes and consoles can block a read.
pub fn wait_ready(fd: Fd, interest: Interest, ms: i32) -> bool {
    if interest == Interest::Write {
        return true;
    }
    let handle = fd as RawHandle;
    // SAFETY: plain query.
    match unsafe { GetFileType(handle) } {
        FILE_TYPE_PIPE => {
            let mut waited = 0;
            loop {
                let mut avail = 0u32;
                // SAFETY: `avail` is writable.
                let r = unsafe {
                    PeekNamedPipe(
                        handle,
                        std::ptr::null_mut(),
                        0,
                        std::ptr::null_mut(),
                        &mut avail,
                        std::ptr::null_mut(),
                    )
                };
                if r == 0 || avail > 0 {
                    return true;
                }
                if waited >= ms {
                    return false;
                }
                pause_2ms();
                waited += 2;
            }
        }
        FILE_TYPE_CHAR if is_console(handle) => {
            let mut waited = 0;
            loop {
                // SAFETY: polling a console input handle.
                if unsafe { WaitForSingleObject(handle, 0) } == WAIT_OBJECT_0 {
                    return true;
                }
                if waited >= ms {
                    return false;
                }
                pause_2ms();
                waited += 2;
            }
        }
        _ => true,
    }
}
