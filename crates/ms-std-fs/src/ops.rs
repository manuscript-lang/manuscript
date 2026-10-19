//! Path-based filesystem operations, ported from `osFileSystem` in `pkg/runtime/fs.go`.
//!
//! Relative paths resolve against the live working directory (the operating system does that), so
//! no path is joined here except where Go joins them. All failures are [`Fail`] values.
use crate::err::{Fail, Res, read_failure};
use crate::path;
use crate::sys::{self, CPath, Errno};
use alloc::vec::Vec;
use core::ffi::CStr;
use ms_rt_abi::{STATUS_LIMIT_EXCEEDED, STATUS_UNSUPPORTED};
use ms_std_rt::poll_cancel;

pub const UNLIMITED: i64 = i64::MAX;

fn cpath(path: &[u8]) -> Res<CPath> {
    CPath::new(path).ok_or_else(Fail::invalid)
}

/// `optionLimit`: a missing limit is unlimited, a negative one is invalid.
pub fn limit(has: bool, value: i64) -> Res<i64> {
    match (has, value) {
        (false, _) => Ok(UNLIMITED),
        (true, v) if v >= 0 => Ok(v),
        _ => Err(Fail::invalid()),
    }
}

fn valid_utf8(bytes: &[u8]) -> bool {
    core::str::from_utf8(bytes).is_ok()
}

// ---------------------------------------------------------------------------
// Whole-file reads and writes
// ---------------------------------------------------------------------------

/// `readBounded`: reads to end of file, failing when more than `max` bytes arrive.
pub fn read_bounded(fd: i32, max: i64) -> Result<Vec<u8>, Fail> {
    const CHUNK: usize = 32 * 1024;
    let mut out: Vec<u8> = Vec::new();
    let mut buf = alloc::vec![0u8; (max.min(CHUNK as i64 - 1) as usize) + 1];
    loop {
        poll_cancel();
        let remaining = max - out.len() as i64;
        let want = if remaining < buf.len() as i64 {
            remaining as usize + 1
        } else {
            buf.len()
        };
        let n = match sys::read(fd, &mut buf[..want]) {
            Ok(n) => n,
            Err(_) => return Err(read_failure(false)),
        };
        if n as i64 > remaining {
            return Err(read_failure(true));
        }
        if n == 0 {
            return Ok(out);
        }
        out.extend_from_slice(&buf[..n]);
    }
}

pub fn read_file(path: &[u8], max: i64) -> Res<Vec<u8>> {
    let p = cpath(path)?;
    let fd = sys::open(&p, libc::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", path))?;
    let result = (|| {
        if let Ok(st) = sys::fstat(fd)
            && sys::is_dir(&st)
        {
            return Err(Fail::invalid());
        }
        read_bounded(fd, max)
    })();
    let _ = sys::close(fd);
    result
}

fn write_all(fd: i32, mut data: &[u8], path: &[u8]) -> Res<()> {
    while !data.is_empty() {
        poll_cancel();
        let end = data.len().min(65536);
        let n = sys::write(fd, &data[..end]).map_err(|e| Fail::errno(e, "write", path))?;
        if n == 0 {
            return Err(Fail::failed("short write"));
        }
        data = &data[n..];
    }
    Ok(())
}

fn write_with(path: &[u8], flags: i32, data: &[u8]) -> Res<()> {
    let p = cpath(path)?;
    let fd = sys::open(&p, libc::O_WRONLY | libc::O_CREAT | flags, 0o600)
        .map_err(|e| Fail::errno(e, "open", path))?;
    let written = write_all(fd, data, path);
    let closed = sys::close(fd).map_err(|e| Fail::errno(e, "close", path));
    written.and(closed)
}

pub fn write_file(path: &[u8], data: &[u8], replace: bool) -> Res<()> {
    write_with(
        path,
        if replace { libc::O_TRUNC } else { libc::O_EXCL },
        data,
    )
}

pub fn append_file(path: &[u8], data: &[u8]) -> Res<()> {
    write_with(path, libc::O_APPEND, data)
}

pub fn copy_file(source: &[u8], destination: &[u8], replace: bool, max: i64) -> Res<()> {
    let s = cpath(source)?;
    cpath(destination)?;
    let fd = sys::open(&s, libc::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", source))?;
    let data = read_bounded(fd, max);
    let _ = sys::close(fd);
    write_file(destination, &data?, replace)
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

/// Everything `FileInfo` reports; times are `(seconds, nanoseconds)` with nanoseconds in `0..1e9`.
#[derive(Debug)]
pub struct Info {
    pub name: Vec<u8>,
    pub size: i64,
    pub mode: i64,
    pub permissions: i64,
    pub modified: (i64, i64),
    pub accessed: (i64, i64),
    pub changed: (i64, i64),
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

pub const KIND_DIRECTORY: u32 = 1;
pub const KIND_SYMLINK: u32 = 2;
pub const KIND_REGULAR: u32 = 4;
pub const KIND_FIFO: u32 = 8;
pub const KIND_SOCKET: u32 = 16;
pub const KIND_BLOCK_DEVICE: u32 = 32;
pub const KIND_CHAR_DEVICE: u32 = 64;

impl Info {
    pub fn kinds(&self) -> u32 {
        match self.mode & 0o170000 {
            0o040000 => KIND_DIRECTORY,
            0o120000 => KIND_SYMLINK,
            0o100000 => KIND_REGULAR,
            0o010000 => KIND_FIFO,
            0o140000 => KIND_SOCKET,
            0o060000 => KIND_BLOCK_DEVICE,
            0o020000 => KIND_CHAR_DEVICE,
            _ => 0,
        }
    }
}

fn nanos((s, n): (i64, i64)) -> (i64, i64) {
    (s + n.div_euclid(1_000_000_000), n.rem_euclid(1_000_000_000))
}

pub fn info_of(st: &libc::stat, name: &[u8], birth: Option<(i64, i64)>) -> Info {
    Info {
        name: name.to_vec(),
        size: st.st_size as i64,
        mode: (st.st_mode & 0o177777) as i64,
        permissions: (st.st_mode & 0o7777) as i64,
        modified: nanos((st.st_mtime as i64, st.st_mtime_nsec as i64)),
        accessed: nanos((st.st_atime as i64, st.st_atime_nsec as i64)),
        changed: nanos((st.st_ctime as i64, st.st_ctime_nsec as i64)),
        created: birth.map(nanos),
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

pub fn stat(path: &[u8], follow: bool) -> Res<Info> {
    let p = cpath(path)?;
    let st = sys::stat(&p, follow)
        .map_err(|e| Fail::errno(e, if follow { "stat" } else { "lstat" }, path))?;
    let name = path::stat_name(path);
    if !valid_utf8(name) {
        return Err(Fail::status(STATUS_UNSUPPORTED));
    }
    Ok(info_of(&st, name, sys::birth_time(&p, follow)))
}

#[derive(Debug)]
pub struct Entry {
    pub name: Vec<u8>,
    pub directory: bool,
    pub symlink: bool,
}

/// `(is directory, is symlink)` of an entry, from `d_type` or an `lstat` when the filesystem reports none.
pub fn entry_kind(dir: &[u8], name: &[u8], kind: u8) -> (bool, bool) {
    if kind != sys::DT_UNKNOWN {
        return (kind == sys::DT_DIR, kind == sys::DT_LNK);
    }
    let full = path::join(dir, name);
    match CPath::new(&full).and_then(|c| sys::stat(&c, false).ok()) {
        Some(st) => (
            st.st_mode & libc::S_IFMT == libc::S_IFDIR,
            st.st_mode & libc::S_IFMT == libc::S_IFLNK,
        ),
        None => (false, false),
    }
}

pub fn list(path: &[u8], max: i64) -> Res<Vec<Entry>> {
    let p = cpath(path)?;
    let st = sys::stat(&p, true).map_err(|e| Fail::errno(e, "open", path))?;
    if !sys::is_dir(&st) {
        return Err(Fail::invalid());
    }
    let raw = sys::read_dir(&p).map_err(|e| Fail::errno(e, "readdirent", path))?;
    let mut out: Vec<Entry> = Vec::new();
    for (name, kind) in raw {
        poll_cancel();
        if out.len() as i64 >= max {
            return Err(Fail::status(STATUS_LIMIT_EXCEEDED));
        }
        if !valid_utf8(&name) {
            return Err(Fail::status(STATUS_UNSUPPORTED));
        }
        let (directory, symlink) = entry_kind(path, &name, kind);
        out.push(Entry {
            name,
            directory,
            symlink,
        });
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}

// ---------------------------------------------------------------------------
// Directories, removal, links
// ---------------------------------------------------------------------------

fn mkdir_all(path: &[u8]) -> Result<(), (Errno, Vec<u8>)> {
    let p = CPath::new(path).ok_or((libc::EINVAL, path.to_vec()))?;
    match sys::stat(&p, true) {
        Ok(st) if sys::is_dir(&st) => return Ok(()),
        Ok(_) => return Err((libc::ENOTDIR, path.to_vec())),
        Err(_) => {}
    }
    let mut i = path.len();
    while i > 0 && path[i - 1] == b'/' {
        i -= 1;
    }
    let mut j = i;
    while j > 0 && path[j - 1] != b'/' {
        j -= 1;
    }
    if j > 1 {
        mkdir_all(&path[..j - 1])?;
    }
    match sys::mkdir(&p, 0o700) {
        Ok(()) => Ok(()),
        Err(e) => match sys::stat(&p, false) {
            Ok(st) if sys::is_dir(&st) => Ok(()),
            _ => Err((e, path.to_vec())),
        },
    }
}

pub fn create_directory(path: &[u8], recursive: bool) -> Res<()> {
    let p = cpath(path)?;
    if recursive {
        return mkdir_all(path).map_err(|(e, at)| Fail::errno(e, "mkdir", &at));
    }
    sys::mkdir(&p, 0o700).map_err(|e| Fail::errno(e, "mkdir", path))
}

/// `os.Remove`: `unlink`, then `rmdir`.
fn remove_one(p: &CPath) -> Result<(), Errno> {
    let e = match sys::unlink(p) {
        Ok(()) => return Ok(()),
        Err(e) => e,
    };
    match sys::rmdir(p) {
        Ok(()) => Ok(()),
        Err(e1) => Err(if e1 != libc::ENOTDIR { e1 } else { e }),
    }
}

fn same_file(a: &libc::stat, b: &libc::stat) -> bool {
    a.st_dev == b.st_dev && a.st_ino == b.st_ino
}

fn eval_symlinks_or(p: &[u8]) -> Result<Vec<u8>, Errno> {
    eval_symlinks(p)
}

/// `removalPath`: refuses the working directory, its ancestors and the root, before touching anything.
fn removal_path(s: &[u8]) -> Result<Vec<u8>, Fail> {
    let b = path::base(s);
    if s.is_empty() || b == b"." || b == b".." {
        return Err(Fail::invalid());
    }
    let cwd = sys::getcwd().map_err(|_| Fail::invalid())?;
    let mut p = if path::is_abs(s) {
        s.to_vec()
    } else {
        path::join(&cwd, s)
    };
    let clean = path::clean(&p);
    if path::dir(&clean) == clean {
        return Err(Fail::invalid());
    }
    while p.last() == Some(&b'/') {
        p.pop();
    }
    let mut base = eval_symlinks_or(&cwd).map_err(|e| Fail::errno(e, "lstat", &cwd))?;
    let pc = CPath::new(&p).ok_or_else(Fail::invalid)?;
    let info = match sys::stat(&pc, false) {
        Err(libc::ENOENT) => return Ok(p),
        Err(e) => return Err(Fail::errno(e, "lstat", &p)),
        Ok(st) => st,
    };
    if !sys::is_dir(&info) {
        return Ok(p);
    }
    loop {
        let bc = CPath::new(&base).ok_or_else(Fail::invalid)?;
        let ancestor = sys::stat(&bc, true).map_err(|e| Fail::errno(e, "stat", &base))?;
        if same_file(&info, &ancestor) {
            return Err(Fail::invalid());
        }
        let parent = path::dir(&base);
        if parent == base {
            break;
        }
        base = parent;
    }
    Ok(p)
}

fn remove_tree_at(dirfd: i32, name: &CStr, display: &[u8]) -> Res<()> {
    poll_cancel();
    // SAFETY: `name` is NUL-terminated; the directory is opened without following symlinks.
    let fd = unsafe {
        libc::openat(
            dirfd,
            name.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        return Err(Fail::errno(sys::errno(), "openat", display));
    }
    // SAFETY: `fd` is an open directory descriptor and is handed to `fdopendir`.
    let dir = unsafe { libc::fdopendir(fd) };
    if dir.is_null() {
        let e = sys::errno();
        let _ = sys::close(fd);
        return Err(Fail::errno(e, "fdopendir", display));
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
        names.push((n.to_vec(), unsafe { (*ent).d_type } == sys::DT_DIR));
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
            } else if matches!(sys::errno(), libc::EISDIR | libc::EPERM) {
                remove_tree_at(fd, c, &child)
            } else {
                Err(Fail::errno(sys::errno(), "unlinkat", &child))
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
        return Err(Fail::errno(sys::errno(), "unlinkat", display));
    }
    Ok(())
}

pub fn remove_tree(path: &[u8]) -> Res<()> {
    poll_cancel();
    let p = cpath(path)?;
    let st = match sys::stat(&p, false) {
        Err(libc::ENOENT) => return Ok(()),
        Err(e) => return Err(Fail::errno(e, "lstat", path)),
        Ok(st) => st,
    };
    if !sys::is_dir(&st) {
        return sys::unlink(&p).map_err(|e| Fail::errno(e, "remove", path));
    }
    let mut full = path.to_vec();
    full.push(0);
    let c = CStr::from_bytes_with_nul(&full).map_err(|_| Fail::invalid())?;
    remove_tree_at(libc::AT_FDCWD, c, path)
}

pub fn remove(path: &[u8], recursive: bool) -> Res<()> {
    cpath(path)?;
    let p = removal_path(path)?;
    if recursive {
        return remove_tree(&p);
    }
    let c = cpath(&p)?;
    remove_one(&c).map_err(|e| Fail::errno(e, "remove", &p))
}

pub fn rename(source: &[u8], destination: &[u8]) -> Res<()> {
    let (a, b) = (cpath(source)?, cpath(destination)?);
    sys::rename(&a, &b).map_err(|e| Fail::errno_paths(e, "rename", &[source, destination]))
}

pub fn read_link(path: &[u8]) -> Res<Vec<u8>> {
    let p = cpath(path)?;
    let target = sys::readlink(&p).map_err(|e| Fail::errno(e, "readlink", path))?;
    if !valid_utf8(&target) {
        return Err(Fail::status(STATUS_UNSUPPORTED));
    }
    Ok(target)
}

pub fn create_link(path: &[u8], target: &[u8]) -> Res<()> {
    let p = cpath(path)?;
    let t = cpath(target)?;
    sys::symlink(&t, &p).map_err(|e| Fail::errno_paths(e, "symlink", &[target, path]))
}

pub fn hard_link(source: &[u8], destination: &[u8]) -> Res<()> {
    let (a, b) = (cpath(source)?, cpath(destination)?);
    sys::link(&a, &b).map_err(|e| Fail::errno_paths(e, "link", &[source, destination]))
}

/// `filepath.EvalSymlinks` (Go's `walkSymlinks`).
pub fn eval_symlinks(original: &[u8]) -> Result<Vec<u8>, Errno> {
    let mut path: Vec<u8> = original.to_vec();
    let mut vol_len = 0;
    if !path.is_empty() && path[0] == b'/' {
        vol_len = 1;
    }
    let mut dest: Vec<u8> = path[..vol_len].to_vec();
    let mut links = 0;
    let (mut start, mut end) = (vol_len, vol_len);
    while start < path.len() {
        start = end;
        while start < path.len() && path[start] == b'/' {
            start += 1;
        }
        end = start;
        while end < path.len() && path[end] != b'/' {
            end += 1;
        }
        if end == start {
            break;
        }
        let part = path[start..end].to_vec();
        if part == b"." {
            continue;
        }
        if part == b".." {
            let mut r = dest.len() as isize - 1;
            while r >= vol_len as isize {
                if dest[r as usize] == b'/' {
                    break;
                }
                r -= 1;
            }
            if r < vol_len as isize || dest[(r + 1) as usize..] == *b".." {
                if dest.len() > vol_len {
                    dest.push(b'/');
                }
                dest.extend_from_slice(b"..");
            } else {
                dest.truncate(r as usize);
            }
            continue;
        }
        if !dest.is_empty() && dest.last() != Some(&b'/') {
            dest.push(b'/');
        }
        dest.extend_from_slice(&part);
        let c = CPath::new(&dest).ok_or(libc::ENOENT)?;
        let st = sys::stat(&c, false)?;
        if st.st_mode & libc::S_IFMT != libc::S_IFLNK {
            if !sys::is_dir(&st) && end < path.len() {
                return Err(libc::ENOTDIR);
            }
            continue;
        }
        links += 1;
        if links > 255 {
            return Err(libc::ELOOP);
        }
        let link = sys::readlink(&c)?;
        let mut next = link.clone();
        next.extend_from_slice(&path[end..]);
        path = next;
        if link.first() == Some(&b'/') {
            dest = alloc::vec![b'/'];
            end = 1;
            vol_len = 1;
        } else {
            let mut r = dest.len() as isize - 1;
            while r >= vol_len as isize {
                if dest[r as usize] == b'/' {
                    break;
                }
                r -= 1;
            }
            if r < vol_len as isize {
                dest.truncate(vol_len);
            } else {
                dest.truncate(r as usize);
            }
            end = 0;
        }
        start = end;
    }
    Ok(path::clean(&dest))
}

pub fn canonicalize(path: &[u8]) -> Res<Vec<u8>> {
    cpath(path)?;
    let s = eval_symlinks(path).map_err(|e| Fail::errno(e, "lstat", path))?;
    if !valid_utf8(&s) {
        return Err(Fail::status(STATUS_UNSUPPORTED));
    }
    Ok(s)
}

// ---------------------------------------------------------------------------
// Temporary directories
// ---------------------------------------------------------------------------

pub fn temporary_root() -> Vec<u8> {
    match sys::env(c"TMPDIR") {
        Some(d) if !d.is_empty() => d,
        _ => b"/tmp".to_vec(),
    }
}

pub fn valid_prefix(prefix: &[u8]) -> bool {
    !prefix.is_empty() && !prefix.iter().any(|&c| c == b'/' || c == b'\\' || c == 0)
}

/// `os.MkdirTemp("", pattern)`: a `*` in the pattern marks where the random digits go.
pub fn temporary_directory(pattern: &[u8]) -> Res<Vec<u8>> {
    if !valid_prefix(pattern) {
        return Err(Fail::invalid());
    }
    let (prefix, suffix) = match pattern.iter().rposition(|&c| c == b'*') {
        Some(i) => (&pattern[..i], &pattern[i + 1..]),
        None => (pattern, &pattern[..0]),
    };
    let mut dir = temporary_root();
    if dir.last() != Some(&b'/') {
        dir.push(b'/');
    }
    let mut tries = 0;
    loop {
        let mut name = dir.clone();
        name.extend_from_slice(prefix);
        name.extend_from_slice(alloc::format!("{}", sys::random_u32()).as_bytes());
        name.extend_from_slice(suffix);
        let c = cpath(&name)?;
        match sys::mkdir(&c, 0o700) {
            Ok(()) => return Ok(name),
            Err(libc::EEXIST) => {
                tries += 1;
                if tries < 10000 {
                    continue;
                }
                return Err(Fail::errno(libc::EEXIST, "mkdirtemp", &name));
            }
            Err(e) => return Err(Fail::errno(e, "mkdir", &name)),
        }
    }
}

// ---------------------------------------------------------------------------
// Attributes
// ---------------------------------------------------------------------------

pub fn stat_filesystem(path: &[u8]) -> Res<sys::FsStat> {
    let p = cpath(path)?;
    sys::statfs(&p).map_err(|e| Fail::errno(e, "statfs", path))
}

pub fn chmod_link(path: &[u8], mode: i64) -> Res<()> {
    cpath(path)?;
    if !(0..=0o7777).contains(&mode) {
        return Err(Fail::invalid());
    }
    #[cfg(target_os = "macos")]
    {
        let c = cpath(path)?;
        // SAFETY: `c` is NUL-terminated.
        if unsafe {
            libc::fchmodat(
                libc::AT_FDCWD,
                c.as_ptr(),
                mode as libc::mode_t,
                libc::AT_SYMLINK_NOFOLLOW,
            )
        } != 0
        {
            return Err(Fail::errno(sys::errno(), "chmod", path));
        }
        return Ok(());
    }
    #[cfg(not(target_os = "macos"))]
    Err(Fail::status(STATUS_UNSUPPORTED))
}

pub fn access(path: &[u8], mode: i64) -> Res<()> {
    let p = cpath(path)?;
    if !(0..=7).contains(&mode) {
        return Err(Fail::invalid());
    }
    sys::access(&p, mode as i32).map_err(|e| Fail::errno(e, "access", path))
}

pub fn chmod(path: &[u8], mode: i64) -> Res<()> {
    let p = cpath(path)?;
    if !(0..=0o7777).contains(&mode) {
        return Err(Fail::invalid());
    }
    sys::chmod(&p, mode as u32).map_err(|e| Fail::errno(e, "chmod", path))
}

pub fn chown(path: &[u8], uid: i64, gid: i64, follow: bool) -> Res<()> {
    let p = cpath(path)?;
    if uid < -1 || gid < -1 || uid > 2_147_483_647 || gid > 2_147_483_647 {
        return Err(Fail::invalid());
    }
    sys::chown(&p, uid, gid, follow)
        .map_err(|e| Fail::errno(e, if follow { "chown" } else { "lchown" }, path))
}

pub fn truncate(path: &[u8], size: i64) -> Res<()> {
    let p = cpath(path)?;
    if size < 0 {
        return Err(Fail::invalid());
    }
    sys::truncate(&p, size).map_err(|e| Fail::errno(e, "truncate", path))
}

pub fn set_times(path: &[u8], accessed: (i64, i64), modified: (i64, i64), follow: bool) -> Res<()> {
    let p = cpath(path)?;
    sys::utimens(&p, accessed, modified, follow).map_err(|e| Fail::errno(e, "chtimes", path))
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::string::String;
    use ms_rt_abi::{
        STATUS_ALREADY_EXISTS, STATUS_INVALID_INPUT, STATUS_NOT_EMPTY, STATUS_NOT_FOUND,
    };

    fn scratch(name: &str) -> Vec<u8> {
        let mut dir = temporary_directory(b"msfs-test-").unwrap();
        dir.push(b'/');
        dir.extend_from_slice(name.as_bytes());
        dir
    }

    fn sub(dir: &[u8], name: &str) -> Vec<u8> {
        path::join(dir, name.as_bytes())
    }

    #[test]
    fn files_round_trip_and_fail_like_go() {
        let root = scratch("a");
        create_directory(&root, true).unwrap();
        let f = sub(&root, "f.txt");
        write_file(&f, b"hello", false).unwrap();
        assert_eq!(
            write_file(&f, b"x", false).unwrap_err().status,
            STATUS_ALREADY_EXISTS
        );
        write_file(&f, b"hello world", true).unwrap();
        append_file(&f, b"!").unwrap();
        assert_eq!(read_file(&f, UNLIMITED).unwrap(), b"hello world!");
        assert_eq!(read_file(&f, 5).unwrap_err().status, STATUS_LIMIT_EXCEEDED);
        assert_eq!(
            read_file(&root, UNLIMITED).unwrap_err().status,
            STATUS_INVALID_INPUT
        );
        assert_eq!(
            read_file(&sub(&root, "none"), UNLIMITED)
                .unwrap_err()
                .status,
            STATUS_NOT_FOUND
        );
        assert_eq!(
            read_file(b"", UNLIMITED).unwrap_err().status,
            STATUS_INVALID_INPUT
        );
        let info = stat(&f, true).unwrap();
        assert_eq!(
            (info.size, info.name.as_slice(), info.kinds()),
            (12, b"f.txt".as_slice(), KIND_REGULAR)
        );
        assert_eq!(info.permissions, 0o600);
        copy_file(&f, &sub(&root, "g"), false, UNLIMITED).unwrap();
        rename(&sub(&root, "g"), &sub(&root, "h")).unwrap();
        create_link(&sub(&root, "l"), b"f.txt").unwrap();
        assert_eq!(read_link(&sub(&root, "l")).unwrap(), b"f.txt");
        let names: Vec<String> = list(&root, UNLIMITED)
            .unwrap()
            .iter()
            .map(|e| String::from_utf8(e.name.clone()).unwrap())
            .collect();
        assert_eq!(names, ["f.txt", "h", "l"]);
        assert_eq!(list(&root, 2).unwrap_err().status, STATUS_LIMIT_EXCEEDED);
        assert!(list(&root, UNLIMITED).unwrap()[2].symlink);
        assert_eq!(remove(&root, false).unwrap_err().status, STATUS_NOT_EMPTY);
        remove(&root, true).unwrap();
        assert_eq!(stat(&root, true).unwrap_err().status, STATUS_NOT_FOUND);
        remove(&root, true).unwrap();
        let _ = remove(&path::dir(&root), true);
    }

    #[test]
    fn canonicalize_resolves_links() {
        let root = scratch("c");
        create_directory(&sub(&root, "real/inner"), true).unwrap();
        create_link(&sub(&root, "alias"), b"real").unwrap();
        let got = canonicalize(&sub(&root, "alias/inner/../inner")).unwrap();
        assert_eq!(got, canonicalize(&sub(&root, "real/inner")).unwrap());
        assert!(got.ends_with(b"real/inner"));
        assert_eq!(
            canonicalize(&sub(&root, "missing")).unwrap_err().status,
            STATUS_NOT_FOUND
        );
        remove(&path::dir(&root), true).unwrap();
    }

    #[test]
    fn removal_protects_the_working_directory() {
        assert_eq!(remove(b".", true).unwrap_err().status, STATUS_INVALID_INPUT);
        assert_eq!(remove(b"/", true).unwrap_err().status, STATUS_INVALID_INPUT);
        assert_eq!(
            remove(b"..", false).unwrap_err().status,
            STATUS_INVALID_INPUT
        );
        let cwd = sys::getcwd().unwrap();
        assert_eq!(remove(&cwd, true).unwrap_err().status, STATUS_INVALID_INPUT);
    }

    #[test]
    fn attributes() {
        let root = scratch("t");
        create_directory(&root, true).unwrap();
        let f = sub(&root, "f");
        write_file(&f, b"abcdef", false).unwrap();
        chmod(&f, 0o640).unwrap();
        assert_eq!(stat(&f, true).unwrap().permissions, 0o640);
        truncate(&f, 2).unwrap();
        assert_eq!(read_file(&f, UNLIMITED).unwrap(), b"ab");
        set_times(&f, (1_000_000_000, 5), (1_500_000_000, 7), true).unwrap();
        let i = stat(&f, true).unwrap();
        assert_eq!(
            (i.accessed, i.modified),
            ((1_000_000_000, 5), (1_500_000_000, 7))
        );
        access(&f, 4).unwrap();
        assert_eq!(access(&f, 9).unwrap_err().status, STATUS_INVALID_INPUT);
        assert_eq!(
            chmod_link(&f, 0o600).unwrap_err().status,
            STATUS_UNSUPPORTED
        );
        assert!(stat_filesystem(&root).unwrap().block_size > 0);
        remove(&path::dir(&root), true).unwrap();
    }
}
