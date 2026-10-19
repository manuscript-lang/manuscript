//! The Windows backend. Paths are UTF-8 byte strings converted to UTF-16; a file "descriptor" is a
//! `HANDLE`. Errors are Win32 error codes (`GetLastError`), plus a few Go-style synthetic codes
//! (`APPLICATION_ERROR + n`) where Go's `syscall.Errno` has no Win32 equivalent. Behaviour follows
//! Go's `os` and `syscall` packages on Windows, which is what the Go runtime reports.
use super::{DT_DIR, DT_LNK, DT_REG, DirEntries, Errno, FsStat, Interest, S_IFCHR, S_IFDIR};
use super::{S_IFIFO, S_IFLNK, S_IFREG, Stat};
use alloc::string::String;
use alloc::vec::Vec;
use core::ffi::CStr;
use core::ptr::{null, null_mut};
use windows_sys::Win32::Foundation::{
    CloseHandle, ERROR_ACCESS_DENIED, ERROR_ALREADY_EXISTS, ERROR_BROKEN_PIPE,
    ERROR_CALL_NOT_IMPLEMENTED, ERROR_DIR_NOT_EMPTY, ERROR_FILE_EXISTS, ERROR_FILE_NOT_FOUND,
    ERROR_HANDLE_EOF, ERROR_INSUFFICIENT_BUFFER, ERROR_NO_MORE_FILES, ERROR_PATH_NOT_FOUND,
    ERROR_PIPE_NOT_CONNECTED, FILETIME, GENERIC_READ, GENERIC_WRITE, GetLastError,
    INVALID_HANDLE_VALUE, SetLastError, WAIT_OBJECT_0,
};
use windows_sys::Win32::Storage::FileSystem::{
    BY_HANDLE_FILE_INFORMATION, CREATE_NEW, CreateDirectoryW, CreateFileW, CreateHardLinkW,
    CreateSymbolicLinkW, DeleteFileW, FILE_APPEND_DATA, FILE_ATTRIBUTE_DIRECTORY,
    FILE_ATTRIBUTE_NORMAL, FILE_ATTRIBUTE_READONLY, FILE_ATTRIBUTE_REPARSE_POINT, FILE_BASIC_INFO,
    FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OPEN_REPARSE_POINT, FILE_SHARE_READ, FILE_SHARE_WRITE,
    FILE_TYPE_CHAR, FILE_TYPE_DISK, FILE_TYPE_PIPE, FILE_WRITE_ATTRIBUTES, FileBasicInfo,
    FindClose, FindExInfoBasic, FindExSearchNameMatch, FindFirstFileExW, FindNextFileW,
    FlushFileBuffers, GetDiskFreeSpaceExW, GetDiskFreeSpaceW, GetFileAttributesW,
    GetFileInformationByHandle, GetFileInformationByHandleEx, GetFileType, GetFullPathNameW,
    GetTempPathW, MOVEFILE_REPLACE_EXISTING, MoveFileExW, OPEN_ALWAYS, OPEN_EXISTING, ReadFile,
    RemoveDirectoryW, SYMBOLIC_LINK_FLAG_DIRECTORY, SetEndOfFile, SetFileAttributesW,
    SetFileInformationByHandle, SetFilePointerEx, TRUNCATE_EXISTING, WIN32_FIND_DATAW, WriteFile,
};
use windows_sys::Win32::System::Console::{
    GetConsoleMode, GetStdHandle, ReadConsoleW, STD_ERROR_HANDLE, STD_INPUT_HANDLE,
    STD_OUTPUT_HANDLE, WriteConsoleW,
};
use windows_sys::Win32::System::Diagnostics::Debug::{
    FORMAT_MESSAGE_FROM_SYSTEM, FORMAT_MESSAGE_IGNORE_INSERTS, FormatMessageW,
};
use windows_sys::Win32::System::Environment::GetCurrentDirectoryW;
use windows_sys::Win32::System::IO::{DeviceIoControl, OVERLAPPED};
use windows_sys::Win32::System::Ioctl::FSCTL_GET_REPARSE_POINT;
use windows_sys::Win32::System::Pipes::PeekNamedPipe;
use windows_sys::Win32::System::Threading::{Sleep, WaitForSingleObject};

/// A file handle.
pub type Fd = isize;

const APPLICATION_ERROR: i32 = 1 << 29;

/// Go's invented `syscall.Errno` values, the ones its Windows file code returns itself.
pub const ENOENT: Errno = APPLICATION_ERROR + 1;
pub const EEXIST: Errno = APPLICATION_ERROR + 2;
pub const ENOTDIR: Errno = APPLICATION_ERROR + 3;
pub const EINVAL: Errno = APPLICATION_ERROR + 4;
pub const EIO: Errno = APPLICATION_ERROR + 5;
pub const ELOOP: Errno = APPLICATION_ERROR + 6;
pub const EAGAIN: Errno = APPLICATION_ERROR + 7;
pub const EISDIR: Errno = APPLICATION_ERROR + 8;
pub const EBADF: Errno = APPLICATION_ERROR + 9;
pub const EWINDOWS: Errno = APPLICATION_ERROR + 10;
pub const ENOSYS: Errno = APPLICATION_ERROR + 11;

const ERROR_NOT_SUPPORTED: Errno = 50;
const ERROR_BAD_NETPATH: Errno = 53;

/// Go's `syscall.O_*` values on Windows.
pub const O_RDONLY: i32 = 0x0;
pub const O_WRONLY: i32 = 0x1;
pub const O_RDWR: i32 = 0x2;
pub const O_CREAT: i32 = 0x40;
pub const O_EXCL: i32 = 0x80;
pub const O_TRUNC: i32 = 0x200;
pub const O_APPEND: i32 = 0x400;
pub const O_SYNC: i32 = 0x1000;

const IO_REPARSE_TAG_SYMLINK: u32 = 0xA000_000C;
const IO_REPARSE_TAG_MOUNT_POINT: u32 = 0xA000_0003;
const SYMLINK_FLAG_RELATIVE: u32 = 1;
const FILE_FLAG_WRITE_THROUGH: u32 = 0x8000_0000;
const SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE: u32 = 2;
/// Ticks of 100ns between 1601-01-01 and 1970-01-01.
const EPOCH_DELTA: i64 = 116_444_736_000_000_000;

pub fn errno() -> Errno {
    // SAFETY: reads the calling thread's last-error value.
    unsafe { GetLastError() as Errno }
}

pub fn set_errno(value: Errno) {
    // SAFETY: sets the calling thread's last-error value.
    unsafe { SetLastError(value as u32) };
}

pub fn is_not_found(e: Errno) -> bool {
    matches!(
        e,
        ENOENT | ERROR_FILE_NOT_FOUND_I | ERROR_PATH_NOT_FOUND_I | ERROR_BAD_NETPATH
    )
}

const ERROR_FILE_NOT_FOUND_I: Errno = ERROR_FILE_NOT_FOUND as Errno;
const ERROR_PATH_NOT_FOUND_I: Errno = ERROR_PATH_NOT_FOUND as Errno;
const ERROR_DIR_NOT_EMPTY_I: Errno = ERROR_DIR_NOT_EMPTY as Errno;
const ERROR_ALREADY_EXISTS_I: Errno = ERROR_ALREADY_EXISTS as Errno;
const ERROR_FILE_EXISTS_I: Errno = ERROR_FILE_EXISTS as Errno;
const ERROR_ACCESS_DENIED_I: Errno = ERROR_ACCESS_DENIED as Errno;
/// `ERROR_DIRECTORY`: a path that is not a directory where one is required.
const ERROR_DIRECTORY_I: Errno = 267;

pub fn is_not_dir(e: Errno) -> bool {
    matches!(e, ENOTDIR | ERROR_DIRECTORY_I)
}

pub fn is_exists(e: Errno) -> bool {
    matches!(
        e,
        EEXIST | ERROR_ALREADY_EXISTS_I | ERROR_FILE_EXISTS_I | ERROR_DIR_NOT_EMPTY_I
    )
}

pub fn write_only(flags: i32) -> bool {
    flags & (O_WRONLY | O_RDWR) == O_WRONLY
}

pub fn read_only(flags: i32) -> bool {
    flags & (O_WRONLY | O_RDWR) == O_RDONLY
}

/// The status an error maps to (`classifyOS` over Go's `syscall.Errno.Is`).
pub fn classify(e: Errno) -> u8 {
    use ms_rt_abi::{
        STATUS_ALREADY_EXISTS, STATUS_FAILED, STATUS_INVALID_INPUT, STATUS_NOT_EMPTY,
        STATUS_NOT_FOUND, STATUS_PERMISSION_DENIED, STATUS_UNSUPPORTED,
    };
    match e {
        ERROR_NOT_SUPPORTED | ERROR_CALL_NOT_IMPLEMENTED_I | ENOSYS | EWINDOWS => {
            STATUS_UNSUPPORTED
        }
        e if is_not_found(e) => STATUS_NOT_FOUND,
        ERROR_DIR_NOT_EMPTY_I => STATUS_NOT_EMPTY,
        EEXIST | ERROR_ALREADY_EXISTS_I | ERROR_FILE_EXISTS_I => STATUS_ALREADY_EXISTS,
        EISDIR | ENOTDIR | EBADF | EINVAL => STATUS_INVALID_INPUT,
        ERROR_ACCESS_DENIED_I => STATUS_PERMISSION_DENIED,
        _ => STATUS_FAILED,
    }
}

const ERROR_CALL_NOT_IMPLEMENTED_I: Errno = ERROR_CALL_NOT_IMPLEMENTED as Errno;

/// Go's text for an error code (`syscall.Errno.Error` on Windows).
pub fn describe(e: Errno) -> String {
    let synthetic = match e {
        ENOENT => Some("no such file or directory"),
        EEXIST => Some("file exists"),
        ENOTDIR => Some("not a directory"),
        EINVAL => Some("invalid argument"),
        EIO => Some("input/output error"),
        ELOOP => Some("too many levels of symbolic links"),
        EAGAIN => Some("resource temporarily unavailable"),
        EISDIR => Some("is a directory"),
        EBADF => Some("bad file descriptor"),
        EWINDOWS => Some("not supported by windows"),
        ENOSYS => Some("function not implemented"),
        _ => None,
    };
    if let Some(text) = synthetic {
        return String::from(text);
    }
    let mut buf = [0u16; 300];
    // English (US), as Go asks first.
    const LANG_ENGLISH_US: u32 = 0x0409;
    // SAFETY: `buf` is writable for its length.
    let mut n = unsafe {
        FormatMessageW(
            FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            null(),
            e as u32,
            LANG_ENGLISH_US,
            buf.as_mut_ptr(),
            buf.len() as u32,
            null(),
        )
    } as usize;
    if n == 0 {
        // SAFETY: as above, with the system default language.
        n = unsafe {
            FormatMessageW(
                FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                null(),
                e as u32,
                0,
                buf.as_mut_ptr(),
                buf.len() as u32,
                null(),
            )
        } as usize;
    }
    if n == 0 {
        return alloc::format!("errno {e}");
    }
    while n > 0 && matches!(buf[n - 1], 0x0a | 0x0d) {
        n -= 1;
    }
    String::from_utf16_lossy(&buf[..n])
}

/// A NUL-terminated UTF-16 path; `None` when it is empty, contains a NUL or is not UTF-8.
pub struct CPath {
    wide: Vec<u16>,
    bytes: Vec<u8>,
}

impl CPath {
    pub fn new(path: &[u8]) -> Option<CPath> {
        if path.is_empty() || path.contains(&0) {
            return None;
        }
        let text = core::str::from_utf8(path).ok()?;
        let mut wide: Vec<u16> = fix_long_path(text.encode_utf16().collect());
        wide.push(0);
        Some(CPath {
            wide,
            bytes: path.to_vec(),
        })
    }

    pub fn as_ptr(&self) -> *const u16 {
        self.wide.as_ptr()
    }

    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }
}

fn utf16_to_utf8(w: &[u16]) -> Vec<u8> {
    String::from_utf16_lossy(w).into_bytes()
}

fn is_slash(c: u16) -> bool {
    c == b'\\' as u16 || c == b'/' as u16
}

/// Go's `fixLongPath`: a path of 248 or more units gets the `\\?\` extended prefix so the Win32
/// path limit does not apply.
fn fix_long_path(path: Vec<u16>) -> Vec<u16> {
    if path.len() < 248 {
        return path;
    }
    let prefix: Vec<u16> = r"\\?\".encode_utf16().collect();
    if path.len() >= 4 && is_slash(path[0]) && is_slash(path[1]) && path[2] == b'?' as u16 {
        return path;
    }
    let mut src = path.clone();
    src.push(0);
    let mut buf: Vec<u16> = alloc::vec![0; 260];
    let full = loop {
        // SAFETY: `src` is NUL-terminated and `buf` is writable for its length.
        let n = unsafe {
            GetFullPathNameW(src.as_ptr(), buf.len() as u32, buf.as_mut_ptr(), null_mut())
        } as usize;
        if n == 0 {
            return path;
        }
        if n > buf.len() {
            buf.resize(n, 0);
            continue;
        }
        buf.truncate(n);
        break buf;
    };
    if full.len() >= 2 && is_slash(full[0]) && is_slash(full[1]) {
        // `\\server\share` becomes `\\?\UNC\server\share`.
        let mut out: Vec<u16> = r"\\?\UNC\".encode_utf16().collect();
        out.extend_from_slice(&full[2..]);
        return out;
    }
    let mut out = prefix;
    out.extend_from_slice(&full);
    out
}

fn wide_nul(s: &str) -> Vec<u16> {
    let mut v: Vec<u16> = s.encode_utf16().collect();
    v.push(0);
    v
}

fn ok(r: i32) -> Result<(), Errno> {
    if r == 0 { Err(errno()) } else { Ok(()) }
}

fn to_unix((ticks_hi, ticks_lo): (u32, u32)) -> (i64, i64) {
    let ticks = ((ticks_hi as i64) << 32 | ticks_lo as i64) - EPOCH_DELTA;
    (
        ticks.div_euclid(10_000_000),
        ticks.rem_euclid(10_000_000) * 100,
    )
}

fn to_filetime((sec, nsec): (i64, i64)) -> FILETIME {
    let ticks = sec.saturating_mul(10_000_000).saturating_add(nsec / 100) + EPOCH_DELTA;
    FILETIME {
        dwLowDateTime: ticks as u32,
        dwHighDateTime: (ticks >> 32) as u32,
    }
}

fn ft(t: FILETIME) -> (i64, i64) {
    to_unix((t.dwHighDateTime, t.dwLowDateTime))
}

fn ticks_unix(ticks: i64) -> (i64, i64) {
    to_unix(((ticks >> 32) as u32, ticks as u32))
}

fn retry_handle(h: isize) -> Result<Fd, Errno> {
    if h == INVALID_HANDLE_VALUE as isize || h == 0 {
        Err(errno())
    } else {
        Ok(h)
    }
}

fn handle(fd: Fd) -> *mut core::ffi::c_void {
    fd as *mut core::ffi::c_void
}

/// `syscall.Open`: `flags` use Go's Windows `O_*` values and `mode` its permission bits.
pub fn open(path: &CPath, flags: i32, mode: u32) -> Result<Fd, Errno> {
    let mut access = match flags & (O_WRONLY | O_RDWR) {
        O_WRONLY => GENERIC_WRITE,
        O_RDWR => GENERIC_READ | GENERIC_WRITE,
        _ => GENERIC_READ,
    };
    if flags & O_CREAT != 0 {
        access |= GENERIC_WRITE;
    }
    if flags & O_APPEND != 0 {
        // Writes must append: keep FILE_APPEND_DATA without FILE_WRITE_DATA, unless truncating.
        if flags & O_TRUNC == 0 {
            access &= !GENERIC_WRITE;
        }
        access |= FILE_APPEND_DATA;
    }
    let mut attrs = if mode & 0o200 == 0 {
        FILE_ATTRIBUTE_READONLY
    } else {
        FILE_ATTRIBUTE_NORMAL
    };
    let create = if flags & (O_CREAT | O_EXCL) == (O_CREAT | O_EXCL) {
        // Never follow a link when creating exclusively.
        attrs |= FILE_FLAG_OPEN_REPARSE_POINT;
        CREATE_NEW
    } else if flags & O_CREAT != 0 {
        OPEN_ALWAYS
    } else if flags & O_TRUNC != 0 {
        TRUNCATE_EXISTING
    } else {
        OPEN_EXISTING
    };
    if flags & (O_WRONLY | O_RDWR) == 0 {
        // A read-only open may name a directory.
        attrs |= FILE_FLAG_BACKUP_SEMANTICS;
    }
    if flags & O_SYNC != 0 {
        attrs |= FILE_FLAG_WRITE_THROUGH;
    }
    // SAFETY: `path` is NUL-terminated.
    let h = unsafe {
        CreateFileW(
            path.as_ptr(),
            access,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            null(),
            create,
            attrs,
            null_mut(),
        )
    };
    let fd = match retry_handle(h as isize) {
        Ok(fd) => fd,
        Err(e) => {
            if e == ERROR_ACCESS_DENIED_I && flags & (O_WRONLY | O_RDWR) != 0 {
                // SAFETY: `path` is NUL-terminated.
                let a = unsafe { GetFileAttributesW(path.as_ptr()) };
                if a != u32::MAX && a & FILE_ATTRIBUTE_DIRECTORY != 0 {
                    return Err(EISDIR);
                }
            }
            return Err(e);
        }
    };
    if flags & O_TRUNC != 0 && create == OPEN_ALWAYS {
        // OPEN_ALWAYS does not truncate; do it explicitly rather than use CREATE_ALWAYS.
        if let Err(e) = ftruncate(fd, 0) {
            let _ = close(fd);
            return Err(e);
        }
    }
    Ok(fd)
}

pub fn close(fd: Fd) -> Result<(), Errno> {
    // SAFETY: closing a handle we own.
    ok(unsafe { CloseHandle(handle(fd)) })
}

/// The descriptor of standard stream `which` (0 input, 1 output, 2 error).
pub fn standard(which: i64) -> Fd {
    let id = match which {
        0 => STD_INPUT_HANDLE,
        1 => STD_OUTPUT_HANDLE,
        _ => STD_ERROR_HANDLE,
    };
    // SAFETY: plain query.
    unsafe { GetStdHandle(id) as isize }
}

/// Whether `fd` is one of the standard output streams the runtime's buffered `print` shares.
pub fn is_output(fd: Fd) -> bool {
    fd != 0 && (fd == standard(1) || fd == standard(2))
}

fn is_console(fd: Fd) -> bool {
    let mut mode = 0;
    // SAFETY: `mode` is writable.
    unsafe { GetConsoleMode(handle(fd), &mut mode) != 0 }
}

pub fn read(fd: Fd, buf: &mut [u8]) -> Result<usize, Errno> {
    if buf.is_empty() {
        return Ok(0);
    }
    if is_console(fd) {
        return read_console(fd, buf);
    }
    let want = buf.len().min(1 << 30) as u32;
    let mut got = 0u32;
    // SAFETY: `buf` is writable for `want` bytes.
    let r = unsafe {
        ReadFile(
            handle(fd),
            buf.as_mut_ptr().cast(),
            want,
            &mut got,
            null_mut(),
        )
    };
    if r == 0 {
        return match errno() as u32 {
            ERROR_BROKEN_PIPE | ERROR_HANDLE_EOF | ERROR_PIPE_NOT_CONNECTED => Ok(0),
            _ => Err(errno()),
        };
    }
    Ok(got as usize)
}

/// Reads a console line as UTF-8; Ctrl-Z alone ends the input, as in Go.
fn read_console(fd: Fd, buf: &mut [u8]) -> Result<usize, Errno> {
    let mut wide = [0u16; 1024];
    // Room for the UTF-8 of every unit read (up to 3 bytes each).
    let units = (buf.len() / 3).clamp(4, wide.len());
    let mut got = 0u32;
    // SAFETY: `wide` is writable for `units` units.
    ok(unsafe {
        ReadConsoleW(
            handle(fd),
            wide.as_mut_ptr().cast(),
            units as u32,
            &mut got,
            null(),
        )
    })?;
    let mut n = got as usize;
    if n == 1 && wide[0] == 0x1a {
        return Ok(0);
    }
    // Keep a high surrogate with its pair by reading one more unit.
    if n > 0 && n < wide.len() && (0xd800..0xdc00).contains(&wide[n - 1]) {
        let mut more = 0u32;
        // SAFETY: one more unit fits in `wide`.
        ok(unsafe {
            ReadConsoleW(
                handle(fd),
                wide[n..].as_mut_ptr().cast(),
                1,
                &mut more,
                null(),
            )
        })?;
        n += more as usize;
    }
    let text = String::from_utf16_lossy(&wide[..n]);
    let bytes = text.as_bytes();
    let take = bytes.len().min(buf.len());
    buf[..take].copy_from_slice(&bytes[..take]);
    Ok(take)
}

pub fn write(fd: Fd, buf: &[u8]) -> Result<usize, Errno> {
    if buf.is_empty() {
        return Ok(0);
    }
    if is_console(fd) {
        let wide: Vec<u16> = String::from_utf8_lossy(buf).encode_utf16().collect();
        let mut done = 0;
        while done < wide.len() {
            let n = (wide.len() - done).min(1 << 14) as u32;
            let mut wrote = 0u32;
            // SAFETY: the slice is readable for `n` units.
            ok(unsafe {
                WriteConsoleW(
                    handle(fd),
                    wide[done..].as_ptr().cast(),
                    n,
                    &mut wrote,
                    null(),
                )
            })?;
            done += wrote as usize;
        }
        return Ok(buf.len());
    }
    let want = buf.len().min(1 << 30) as u32;
    let mut wrote = 0u32;
    // SAFETY: `buf` is readable for `want` bytes.
    ok(unsafe {
        WriteFile(
            handle(fd),
            buf.as_ptr().cast(),
            want,
            &mut wrote,
            null_mut(),
        )
    })?;
    Ok(wrote as usize)
}

/// Runs `f` on the file position, restoring it afterwards (Windows has no `pread`).
fn with_position<T>(fd: Fd, offset: i64, f: impl FnOnce() -> Result<T, Errno>) -> Result<T, Errno> {
    let saved = seek(fd, 0, 1)?;
    seek(fd, offset, 0)?;
    let r = f();
    let _ = seek(fd, saved, 0);
    r
}

/// Reads at `offset`; `Ok(0)` at end of file.
pub fn pread(fd: Fd, buf: &mut [u8], offset: i64) -> Result<usize, Errno> {
    with_position(fd, offset, || read(fd, buf))
}

/// Writes at `offset`.
pub fn pwrite(fd: Fd, buf: &[u8], offset: i64) -> Result<usize, Errno> {
    with_position(fd, offset, || write(fd, buf))
}

/// `SetFilePointerEx` with `origin` 0 (start), 1 (current) or 2 (end); returns the new position.
pub fn seek(fd: Fd, offset: i64, origin: i64) -> Result<i64, Errno> {
    let mut at = 0i64;
    // SAFETY: `at` is writable.
    ok(unsafe { SetFilePointerEx(handle(fd), offset, &mut at, origin as u32) })?;
    Ok(at)
}

/// Moves the position back by `by` bytes (returning read-ahead to the file).
pub fn rewind_by(fd: Fd, by: usize) {
    let _ = seek(fd, -(by as i64), 1);
}

pub fn ftruncate(fd: Fd, size: i64) -> Result<(), Errno> {
    let saved = seek(fd, 0, 1)?;
    let r = seek(fd, size, 0).and_then(|_| {
        // SAFETY: plain call on an open handle.
        ok(unsafe { SetEndOfFile(handle(fd)) })
    });
    let _ = seek(fd, saved, 0);
    r
}

pub fn fsync(fd: Fd) -> Result<(), Errno> {
    // SAFETY: plain call on an open handle.
    ok(unsafe { FlushFileBuffers(handle(fd)) })
}

pub fn fdatasync(fd: Fd) -> Result<(), Errno> {
    fsync(fd)
}

fn basic_info(fd: Fd) -> Result<FILE_BASIC_INFO, Errno> {
    // SAFETY: zeroed `FILE_BASIC_INFO` is a valid out buffer.
    let mut info: FILE_BASIC_INFO = unsafe { core::mem::zeroed() };
    // SAFETY: `info` is writable for its size.
    ok(unsafe {
        GetFileInformationByHandleEx(
            handle(fd),
            FileBasicInfo,
            (&mut info as *mut FILE_BASIC_INFO).cast(),
            core::mem::size_of::<FILE_BASIC_INFO>() as u32,
        )
    })?;
    Ok(info)
}

/// Sets or clears the read-only attribute from the owner write bit, as `os.File.Chmod` does.
pub fn fchmod(fd: Fd, mode: u32) -> Result<(), Errno> {
    let mut info = basic_info(fd)?;
    let attrs = if mode & 0o200 == 0 {
        info.FileAttributes | FILE_ATTRIBUTE_READONLY
    } else {
        info.FileAttributes & !FILE_ATTRIBUTE_READONLY
    };
    if attrs == info.FileAttributes {
        return Ok(());
    }
    info.FileAttributes = if attrs == 0 {
        FILE_ATTRIBUTE_NORMAL
    } else {
        attrs
    };
    // Zero times leave the stamps unchanged.
    info.CreationTime = 0;
    info.LastAccessTime = 0;
    info.LastWriteTime = 0;
    info.ChangeTime = 0;
    // SAFETY: `info` is readable for its size.
    ok(unsafe {
        SetFileInformationByHandle(
            handle(fd),
            FileBasicInfo,
            (&info as *const FILE_BASIC_INFO).cast(),
            core::mem::size_of::<FILE_BASIC_INFO>() as u32,
        )
    })
}

/// Ownership does not exist on Windows (`syscall.EWINDOWS`).
pub fn fchown(_: Fd, _: i64, _: i64) -> Result<(), Errno> {
    Err(EWINDOWS)
}

pub fn futimens(fd: Fd, atime: (i64, i64), mtime: (i64, i64)) -> Result<(), Errno> {
    use windows_sys::Win32::Storage::FileSystem::SetFileTime;
    let (a, m) = (to_filetime(atime), to_filetime(mtime));
    // SAFETY: both times are valid for the call.
    ok(unsafe { SetFileTime(handle(fd), null(), &a, &m) })
}

/// Blocks up to `ms` milliseconds until `fd` is ready; `true` when ready, hung up or failed (the
/// next read or write reports the details). Only pipes and consoles can block a read.
pub fn wait_ready(fd: Fd, interest: Interest, ms: i32) -> bool {
    if interest == Interest::Write {
        return true;
    }
    // SAFETY: plain query.
    match unsafe { GetFileType(handle(fd)) } {
        FILE_TYPE_PIPE => {
            let mut waited = 0;
            loop {
                let mut avail = 0u32;
                // SAFETY: `avail` is writable.
                let r = unsafe {
                    PeekNamedPipe(
                        handle(fd),
                        null_mut(),
                        0,
                        null_mut(),
                        &mut avail,
                        null_mut(),
                    )
                };
                if r == 0 || avail > 0 {
                    return true;
                }
                if waited >= ms {
                    return false;
                }
                // SAFETY: plain sleep.
                unsafe { Sleep(2) };
                waited += 2;
            }
        }
        FILE_TYPE_CHAR if is_console(fd) => {
            // SAFETY: waiting on a console input handle.
            unsafe { WaitForSingleObject(handle(fd), ms.max(0) as u32) == WAIT_OBJECT_0 }
        }
        _ => true,
    }
}

pub fn sleep_ms(ms: i32) {
    // SAFETY: plain sleep.
    unsafe { Sleep(ms.max(0) as u32) };
}

/// Whether reads of a descriptor with this `fstat` result may block indefinitely.
pub fn is_pollable(st: &Stat) -> bool {
    !st.is_regular()
}

fn file_stat(fd: Fd, follow_symlink_info: bool) -> Result<Stat, Errno> {
    let _ = follow_symlink_info;
    // SAFETY: plain query.
    match unsafe { GetFileType(handle(fd)) } {
        FILE_TYPE_CHAR => {
            return Ok(Stat {
                mode: S_IFCHR | 0o666,
                ..Stat::default()
            });
        }
        FILE_TYPE_PIPE => {
            return Ok(Stat {
                mode: S_IFIFO | 0o666,
                ..Stat::default()
            });
        }
        FILE_TYPE_DISK => {}
        _ => return Err(errno()),
    }
    // SAFETY: zeroed struct is a valid out buffer.
    let mut info: BY_HANDLE_FILE_INFORMATION = unsafe { core::mem::zeroed() };
    // SAFETY: `info` is writable.
    ok(unsafe { GetFileInformationByHandle(handle(fd), &mut info) })?;
    let reparse_tag = if info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
        reparse_tag(fd)
    } else {
        0
    };
    let mut perm = if info.dwFileAttributes & FILE_ATTRIBUTE_READONLY != 0 {
        0o444
    } else {
        0o666
    };
    let kind = if reparse_tag == IO_REPARSE_TAG_SYMLINK {
        S_IFLNK
    } else if info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0 {
        perm |= 0o111;
        S_IFDIR
    } else {
        S_IFREG
    };
    let modified = ft(info.ftLastWriteTime);
    Ok(Stat {
        mode: kind | perm,
        size: (info.nFileSizeHigh as i64) << 32 | info.nFileSizeLow as i64,
        modified,
        // Go reports no native access or change times on Windows; both fall back to the
        // modification time.
        accessed: modified,
        changed: modified,
        device: info.dwVolumeSerialNumber as u64,
        inode: (info.nFileIndexHigh as u64) << 32 | info.nFileIndexLow as u64,
        ..Stat::default()
    })
}

/// The creation time of the file behind `fd`.
fn creation_time(fd: Fd) -> Option<(i64, i64)> {
    basic_info(fd).ok().map(|i| ticks_unix(i.CreationTime))
}

pub fn fstat(fd: Fd) -> Result<Stat, Errno> {
    file_stat(fd, true)
}

/// Opens `path` for attribute queries only; a link itself when `follow` is false.
fn open_attributes(path: &CPath, follow: bool) -> Result<Fd, Errno> {
    let mut attrs = FILE_FLAG_BACKUP_SEMANTICS;
    if !follow {
        attrs |= FILE_FLAG_OPEN_REPARSE_POINT;
    }
    // SAFETY: `path` is NUL-terminated.
    let h = unsafe {
        CreateFileW(
            path.as_ptr(),
            0,
            FILE_SHARE_READ | FILE_SHARE_WRITE | 4,
            null(),
            OPEN_EXISTING,
            attrs,
            null_mut(),
        )
    };
    retry_handle(h as isize)
}

pub fn stat(path: &CPath, follow: bool) -> Result<Stat, Errno> {
    let fd = open_attributes(path, follow)?;
    let r = file_stat(fd, follow);
    let _ = close(fd);
    r
}

/// Birth (creation) time of a path.
pub fn birth_time(path: &CPath, follow: bool) -> Option<(i64, i64)> {
    let fd = open_attributes(path, follow).ok()?;
    let t = creation_time(fd);
    let _ = close(fd);
    t
}

/// Birth (creation) time of an open handle.
pub fn birth_time_fd(fd: Fd) -> Option<(i64, i64)> {
    creation_time(fd)
}

/// The reparse tag of an open handle, `0` when it cannot be read.
fn reparse_tag(fd: Fd) -> u32 {
    reparse_buffer(fd).map_or(0, |b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

fn reparse_buffer(fd: Fd) -> Result<Vec<u8>, Errno> {
    let mut buf = alloc::vec![0u8; 16 * 1024];
    let mut returned = 0u32;
    // SAFETY: `buf` is writable for its length.
    ok(unsafe {
        DeviceIoControl(
            handle(fd),
            FSCTL_GET_REPARSE_POINT,
            null(),
            0,
            buf.as_mut_ptr().cast(),
            buf.len() as u32,
            &mut returned,
            null_mut::<OVERLAPPED>(),
        )
    })?;
    buf.truncate(returned as usize);
    if buf.len() < 8 {
        return Err(EINVAL);
    }
    Ok(buf)
}

pub fn mkdir(path: &CPath, _mode: u32) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    ok(unsafe { CreateDirectoryW(path.as_ptr(), null()) })
}

pub fn unlink(path: &CPath) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    ok(unsafe { DeleteFileW(path.as_ptr()) })
}

pub fn rmdir(path: &CPath) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    ok(unsafe { RemoveDirectoryW(path.as_ptr()) })
}

/// `os.Remove`: `DeleteFile`, then `RemoveDirectory`, clearing a read-only attribute on a file.
pub fn remove(p: &CPath) -> Result<(), Errno> {
    let e = match unlink(p) {
        Ok(()) => return Ok(()),
        Err(e) => e,
    };
    let e1 = match rmdir(p) {
        Ok(()) => return Ok(()),
        Err(e1) => e1,
    };
    if e1 == e {
        return Err(e);
    }
    // SAFETY: `p` is NUL-terminated.
    let attrs = unsafe { GetFileAttributesW(p.as_ptr()) };
    if attrs == u32::MAX {
        return Err(errno());
    }
    if attrs & FILE_ATTRIBUTE_DIRECTORY != 0 {
        return Err(e1);
    }
    if attrs & FILE_ATTRIBUTE_READONLY != 0 {
        // SAFETY: `p` is NUL-terminated.
        if unsafe { SetFileAttributesW(p.as_ptr(), attrs & !FILE_ATTRIBUTE_READONLY) } != 0
            && unlink(p).is_ok()
        {
            return Ok(());
        }
    }
    Err(e)
}

pub fn rename(from: &CPath, to: &CPath) -> Result<(), Errno> {
    // SAFETY: both paths are NUL-terminated.
    ok(unsafe { MoveFileExW(from.as_ptr(), to.as_ptr(), MOVEFILE_REPLACE_EXISTING) })
}

/// `os.Symlink`: the target is written with `\`, and a link to a directory is made a directory
/// link. Creating one needs a privilege unless Developer Mode is on.
pub fn symlink(target: &CPath, path: &CPath) -> Result<(), Errno> {
    let mut old: Vec<u8> = target.bytes().to_vec();
    old.iter_mut().for_each(|c| {
        if *c == b'/' {
            *c = b'\\';
        }
    });
    let mut dest = old.clone();
    if crate::path::volume_len(&old) == 0 {
        let vol = crate::path::volume_len(path.bytes());
        if old.first() == Some(&b'\\') {
            // Relative to the volume holding the link.
            if vol > 0 {
                dest = path.bytes()[..vol].to_vec();
                dest.extend_from_slice(&old);
            }
        } else {
            dest = crate::path::dir(path.bytes());
            dest.push(b'\\');
            dest.extend_from_slice(&old);
        }
    }
    let is_dir = CPath::new(&dest)
        .and_then(|c| stat(&c, true).ok())
        .is_some_and(|st| st.is_dir());
    let old_wide = CPath::new(&old).ok_or(EINVAL)?;
    let mut flags = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;
    if is_dir {
        flags |= SYMBOLIC_LINK_FLAG_DIRECTORY;
    }
    // SAFETY: both paths are NUL-terminated.
    let mut r = unsafe { CreateSymbolicLinkW(path.as_ptr(), old_wide.as_ptr(), flags) };
    if !r {
        // The unprivileged flag is unknown before Windows 10 1703; retry without it.
        flags &= !SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;
        // SAFETY: as above.
        r = unsafe { CreateSymbolicLinkW(path.as_ptr(), old_wide.as_ptr(), flags) };
    }
    if r { Ok(()) } else { Err(errno()) }
}

pub fn link(from: &CPath, to: &CPath) -> Result<(), Errno> {
    // SAFETY: both paths are NUL-terminated.
    ok(unsafe { CreateHardLinkW(to.as_ptr(), from.as_ptr(), null()) })
}

/// `os.Readlink` for symbolic links and junctions, with the `\??\` prefix removed.
pub fn readlink(path: &CPath) -> Result<Vec<u8>, Errno> {
    let fd = open_attributes(path, false)?;
    let buf = reparse_buffer(fd);
    let _ = close(fd);
    let buf = buf?;
    let tag = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]);
    let (header, relative) = match tag {
        IO_REPARSE_TAG_SYMLINK => {
            if buf.len() < 20 {
                return Err(EINVAL);
            }
            (
                20,
                u32::from_le_bytes([buf[16], buf[17], buf[18], buf[19]]) & SYMLINK_FLAG_RELATIVE
                    != 0,
            )
        }
        IO_REPARSE_TAG_MOUNT_POINT => (16, false),
        _ => return Err(EINVAL),
    };
    let u16_at = |i: usize| u16::from_le_bytes([buf[i], buf[i + 1]]) as usize;
    let (offset, length) = (u16_at(8), u16_at(10));
    let start = header + offset;
    if start + length > buf.len() {
        return Err(EINVAL);
    }
    let wide: Vec<u16> = buf[start..start + length]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|c| u16::from_le_bytes([c[0], c[1]]))
        .collect();
    let mut s = utf16_to_utf8(&wide);
    if !relative && s.starts_with(br"\??\") {
        s.drain(..4);
        if s.len() >= 2 && s[1] == b':' {
            // `\??\C:\dir`
        } else if s.starts_with(br"UNC\") {
            s.splice(..4, br"\\".iter().copied());
        } else {
            // A volume GUID path has no drive-letter form.
            return Err(EINVAL);
        }
    }
    Ok(s)
}

pub fn chmod(path: &CPath, mode: u32) -> Result<(), Errno> {
    // SAFETY: `path` is NUL-terminated.
    let attrs = unsafe { GetFileAttributesW(path.as_ptr()) };
    if attrs == u32::MAX {
        return Err(errno());
    }
    let new = if mode & 0o200 == 0 {
        attrs | FILE_ATTRIBUTE_READONLY
    } else {
        attrs & !FILE_ATTRIBUTE_READONLY
    };
    if new == attrs {
        return Ok(());
    }
    // SAFETY: `path` is NUL-terminated.
    ok(unsafe { SetFileAttributesW(path.as_ptr(), new) })
}

/// Ownership does not exist on Windows (`syscall.EWINDOWS`).
pub fn chown(_: &CPath, _: i64, _: i64, _: bool) -> Result<(), Errno> {
    Err(EWINDOWS)
}

/// Changing a link's own mode is unsupported.
pub fn chmod_link(_: &CPath, _: u32) -> Result<(), Errno> {
    Err(EWINDOWS)
}

pub fn truncate(path: &CPath, size: i64) -> Result<(), Errno> {
    let fd = open(path, O_WRONLY, 0)?;
    let r = ftruncate(fd, size);
    let _ = close(fd);
    r
}

/// `hostos.Access`: existence, plus an open for reading or writing when asked.
pub fn access(path: &CPath, mode: i32) -> Result<(), Errno> {
    let st = stat(path, true)?;
    if mode == 0 || st.is_dir() {
        return Ok(());
    }
    let flags = if mode & 2 != 0 { O_RDWR } else { O_RDONLY };
    let fd = open(path, flags, 0)?;
    close(fd)
}

/// `os.Chtimes`: sets the times of the file itself; a link cannot be changed in place.
pub fn utimens(
    path: &CPath,
    atime: (i64, i64),
    mtime: (i64, i64),
    follow: bool,
) -> Result<(), Errno> {
    if !follow {
        return Err(EWINDOWS);
    }
    // SAFETY: `path` is NUL-terminated.
    let h = unsafe {
        CreateFileW(
            path.as_ptr(),
            FILE_WRITE_ATTRIBUTES,
            FILE_SHARE_WRITE,
            null(),
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS,
            null_mut(),
        )
    };
    let fd = retry_handle(h as isize)?;
    let r = futimens(fd, atime, mtime);
    let _ = close(fd);
    r
}

fn full_path(path: &CPath) -> Result<Vec<u16>, Errno> {
    let mut buf: Vec<u16> = alloc::vec![0; 260];
    loop {
        // SAFETY: `path` is NUL-terminated and `buf` is writable for its length.
        let n = unsafe {
            GetFullPathNameW(
                path.as_ptr(),
                buf.len() as u32,
                buf.as_mut_ptr(),
                null_mut(),
            )
        } as usize;
        if n == 0 {
            return Err(errno());
        }
        if n > buf.len() {
            buf.resize(n, 0);
            continue;
        }
        buf.truncate(n);
        return Ok(buf);
    }
}

/// `hostos.StatFS`: sizes of the volume holding `path`.
pub fn statfs(path: &CPath) -> Result<FsStat, Errno> {
    let full = full_path(path)?;
    let bytes = utf16_to_utf8(&full);
    let vol = crate::path::volume_len(&bytes);
    let mut root = String::from_utf8_lossy(&bytes[..vol]).into_owned();
    root.push('\\');
    let root = wide_nul(&root);
    let (mut sectors, mut sector_bytes, mut free, mut total) = (0u32, 0u32, 0u32, 0u32);
    // SAFETY: `root` is NUL-terminated and the outputs are writable.
    ok(unsafe {
        GetDiskFreeSpaceW(
            root.as_ptr(),
            &mut sectors,
            &mut sector_bytes,
            &mut free,
            &mut total,
        )
    })?;
    let (mut available_bytes, mut total_bytes, mut free_bytes) = (0u64, 0u64, 0u64);
    // SAFETY: as above.
    ok(unsafe {
        GetDiskFreeSpaceExW(
            root.as_ptr(),
            &mut available_bytes,
            &mut total_bytes,
            &mut free_bytes,
        )
    })?;
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

pub fn getcwd() -> Result<Vec<u8>, Errno> {
    let mut buf: Vec<u16> = alloc::vec![0; 260];
    loop {
        // SAFETY: `buf` is writable for its length.
        let n = unsafe { GetCurrentDirectoryW(buf.len() as u32, buf.as_mut_ptr()) } as usize;
        if n == 0 {
            return Err(errno());
        }
        if n >= buf.len() {
            buf.resize(n + 1, 0);
            continue;
        }
        return Ok(utf16_to_utf8(&buf[..n]));
    }
}

/// An open directory stream over `FindFirstFileEx`.
pub struct Dir {
    find: isize,
    /// The first entry, read by `FindFirstFile` before the first `read_entry`.
    pending: Option<WIN32_FIND_DATAW>,
}

fn entry_of(data: &WIN32_FIND_DATAW) -> Option<(Vec<u8>, u8)> {
    let len = data
        .cFileName
        .iter()
        .position(|&c| c == 0)
        .unwrap_or(data.cFileName.len());
    let name = utf16_to_utf8(&data.cFileName[..len]);
    if name == b"." || name == b".." {
        return None;
    }
    let kind = if data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0
        && data.dwReserved0 == IO_REPARSE_TAG_SYMLINK
    {
        DT_LNK
    } else if data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0 {
        DT_DIR
    } else {
        DT_REG
    };
    Some((name, kind))
}

impl Dir {
    pub fn open(path: &CPath) -> Result<Dir, Errno> {
        // The pattern is the directory's contents: `path\*`.
        let mut pattern: Vec<u16> = path.wide[..path.wide.len() - 1].to_vec();
        if !pattern.last().is_some_and(|&c| is_slash(c)) {
            pattern.push(b'\\' as u16);
        }
        pattern.push(b'*' as u16);
        pattern.push(0);
        // SAFETY: zeroed `WIN32_FIND_DATAW` is a valid out buffer.
        let mut data: WIN32_FIND_DATAW = unsafe { core::mem::zeroed() };
        // SAFETY: `pattern` is NUL-terminated and `data` writable.
        let h = unsafe {
            FindFirstFileExW(
                pattern.as_ptr(),
                FindExInfoBasic,
                (&mut data as *mut WIN32_FIND_DATAW).cast(),
                FindExSearchNameMatch,
                null(),
                2, // FIND_FIRST_EX_LARGE_FETCH
            )
        };
        if h == INVALID_HANDLE_VALUE {
            return Err(errno());
        }
        Ok(Dir {
            find: h as isize,
            pending: Some(data),
        })
    }

    /// The next entry `(name, kind)` excluding `.` and `..`; `None` at the end.
    pub fn read_entry(&mut self) -> Result<Option<(Vec<u8>, u8)>, Errno> {
        loop {
            let data = match self.pending.take() {
                Some(data) => data,
                None => {
                    if self.find == 0 {
                        return Ok(None);
                    }
                    // SAFETY: zeroed `WIN32_FIND_DATAW` is a valid out buffer.
                    let mut data: WIN32_FIND_DATAW = unsafe { core::mem::zeroed() };
                    // SAFETY: the search handle is open and `data` writable.
                    if unsafe { FindNextFileW(self.find as *mut _, &mut data) } == 0 {
                        return match errno() as u32 {
                            ERROR_NO_MORE_FILES => Ok(None),
                            _ => Err(errno()),
                        };
                    }
                    data
                }
            };
            if let Some(entry) = entry_of(&data) {
                return Ok(Some(entry));
            }
        }
    }

    pub fn close(&mut self) {
        if self.find != 0 {
            // SAFETY: the search handle is open and closed once.
            unsafe { FindClose(self.find as *mut _) };
            self.find = 0;
        }
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        self.close();
    }
}

/// Directory entries `(name, kind)`, excluding `.` and `..`.
pub fn read_dir(path: &CPath) -> Result<DirEntries, Errno> {
    let mut dir = Dir::open(path)?;
    let mut out = Vec::new();
    while let Some(entry) = dir.read_entry()? {
        out.push(entry);
    }
    Ok(out)
}

/// Removes a directory tree without following links: a link is deleted, never entered.
pub fn remove_tree(path: &[u8]) -> Result<(), (Errno, &'static str, Vec<u8>)> {
    let fail = |e: Errno, op: &'static str, at: &[u8]| (e, op, at.to_vec());
    let c = CPath::new(path).ok_or_else(|| fail(EINVAL, "remove", path))?;
    let entries = read_dir(&c).map_err(|e| fail(e, "open", path))?;
    for (name, kind) in entries {
        let child = crate::path::join(path, &name);
        if kind == DT_DIR {
            remove_tree(&child)?;
        } else {
            let cc = CPath::new(&child).ok_or_else(|| fail(EINVAL, "remove", &child))?;
            remove(&cc).map_err(|e| fail(e, "remove", &child))?;
        }
    }
    remove(&c).map_err(|e| fail(e, "remove", path))
}

/// Block cloning is not supported (`hostos.CloneFile`).
pub fn clone_file(_: Fd, _: Fd) -> Result<(), Errno> {
    Err(EWINDOWS)
}

/// `os.TempDir`: `GetTempPath` without its trailing `\` (except for a bare drive root).
pub fn temp_dir() -> Vec<u8> {
    let mut buf: Vec<u16> = alloc::vec![0; 260];
    loop {
        // SAFETY: `buf` is writable for its length.
        let n = unsafe { GetTempPathW(buf.len() as u32, buf.as_mut_ptr()) } as usize;
        if n > buf.len() {
            buf.resize(n, 0);
            continue;
        }
        let mut n = n;
        if n == 3 && buf[1] == b':' as u16 && buf[2] == b'\\' as u16 {
            // Keep `C:\`.
        } else if n > 0 && buf[n - 1] == b'\\' as u16 {
            n -= 1;
        }
        return utf16_to_utf8(&buf[..n]);
    }
}

pub fn random_u32() -> u32 {
    use windows_sys::Win32::Security::Cryptography::{
        BCRYPT_USE_SYSTEM_PREFERRED_RNG, BCryptGenRandom,
    };
    let mut v = [0u8; 4];
    // SAFETY: `v` is writable for 4 bytes.
    let status = unsafe {
        BCryptGenRandom(
            null_mut(),
            v.as_mut_ptr(),
            4,
            BCRYPT_USE_SYSTEM_PREFERRED_RNG,
        )
    };
    if status == 0 {
        u32::from_ne_bytes(v)
    } else {
        (&v as *const _ as usize as u32) ^ errno() as u32
    }
}

/// The value of an environment variable.
pub fn env(name: &CStr) -> Option<Vec<u8>> {
    use windows_sys::Win32::System::Environment::GetEnvironmentVariableW;
    let wide = wide_nul(name.to_str().ok()?);
    let mut buf: Vec<u16> = alloc::vec![0; 256];
    loop {
        // SAFETY: `wide` is NUL-terminated and `buf` writable for its length.
        let n =
            unsafe { GetEnvironmentVariableW(wide.as_ptr(), buf.as_mut_ptr(), buf.len() as u32) }
                as usize;
        if n == 0 {
            return None;
        }
        if n >= buf.len() {
            buf.resize(n + 1, 0);
            continue;
        }
        return Some(utf16_to_utf8(&buf[..n]));
    }
}

/// A pipe `(read, write)` for tests.
#[cfg(test)]
pub fn pipe() -> (Fd, Fd) {
    use windows_sys::Win32::System::Pipes::CreatePipe;
    let (mut r, mut w) = (null_mut(), null_mut());
    // SAFETY: both outputs are writable.
    assert_ne!(unsafe { CreatePipe(&mut r, &mut w, null(), 0) }, 0);
    (r as isize, w as isize)
}

#[allow(dead_code)]
const _: u32 = ERROR_INSUFFICIENT_BUFFER;
