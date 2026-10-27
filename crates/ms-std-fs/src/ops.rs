//! Path-based filesystem operations.
//!
//! Relative paths resolve against the live working directory (the operating system does that), so
//! no path is joined here except where Go joins them. All failures are [`Fail`] values.
use crate::err::{Fail, Res, read_failure};
use crate::path;
use crate::sys::{self, CPath, Errno};
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_LIMIT_EXCEEDED, STATUS_UNSUPPORTED};

pub const UNLIMITED: i64 = i64::MAX;

/// `glue::poll_cancel` for code that also runs as a blocking-pool job, where the runtime is off
/// limits: a job never checks for a stop request.
pub(crate) fn poll_cancel() {
    if !ms_rt::glue::pool::on_pool_thread() {
        ms_rt::glue::poll_cancel();
    }
}

/// Runs `f(&input, bytes)` on a blocking-pool thread when other tasks could use the time, so a
/// slow disk stalls only the calling task; otherwise inline. The wait is shielded, so `bytes`
/// may be borrowed, and a stop request takes effect once the call is done. `f` must not call
/// into the runtime (see [`poll_cancel`]). A call made by a job runs inline.
pub(crate) fn offload<I: Send + Sync + 'static, O: Send + 'static>(
    input: I,
    bytes: &[u8],
    f: fn(&I, &[u8]) -> O,
) -> O {
    #[cfg(not(test))]
    if !ms_rt::glue::pool::on_pool_thread() && !ms_rt::glue::pool::alone() {
        return ms_rt::glue::pool::run_shielded(Lane::General, input, bytes, f);
    }
    f(&input, bytes)
}

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

/// A directory entry name as text: bytes that are not UTF-8 become U+FFFD, so one odd name
/// does not make its directory unlistable. Such a name no longer addresses the entry.
pub(crate) fn lossy_name(name: &[u8]) -> Vec<u8> {
    alloc::string::String::from_utf8_lossy(name)
        .into_owned()
        .into_bytes()
}

// ---------------------------------------------------------------------------
// Whole-file reads and writes
// ---------------------------------------------------------------------------

/// `readBounded`: reads to end of file, failing when more than `max` bytes arrive.
pub fn read_bounded(fd: sys::Fd, max: i64) -> Result<Vec<u8>, Fail> {
    read_limited(fd, max, true)
}

/// Parks the task until `fd` can be read, so a pipe with no data yet neither stalls the other
/// tasks nor ignores a stop request.
fn wait_readable(fd: sys::Fd) {
    #[cfg(all(unix, not(test)))]
    ms_rt::glue::task_wait_fd(fd, ms_rt::glue::WAIT_READ, -1);
    #[cfg(any(not(unix), test))]
    let _ = fd;
}

/// Opens `path`. A named pipe opened for reading would block in `open(2)` until a writer
/// arrives, so it is opened without waiting and then switched back to blocking mode; reads wait
/// for data through `wait_readable`.
pub(crate) fn open_waitless(path: &CPath, flags: i32, mode: u32) -> Result<sys::Fd, Errno> {
    #[cfg(unix)]
    if flags & 3 == sys::O_RDONLY && sys::stat(path, true).is_ok_and(|st| st.is_fifo()) {
        let fd = sys::open(path, flags | libc::O_NONBLOCK, mode)?;
        sys::clear_nonblocking(fd);
        return Ok(fd);
    }
    sys::open(path, flags, mode)
}

/// `read_bounded`; `cancellable` checks for a stop request between reads, which a blocking-pool
/// thread must not do. A cancellable read of a pipe or device also waits for it to be readable.
fn read_limited(fd: sys::Fd, max: i64, cancellable: bool) -> Result<Vec<u8>, Fail> {
    const CHUNK: usize = 32 * 1024;
    const LARGEST_READ: usize = 1 << 20;
    // A regular file of known size is read into one buffer of that size (plus a byte to see the
    // end), usually with a single read, instead of through a chunk buffer and copies.
    let stat = sys::fstat(fd).ok();
    let known = stat
        .as_ref()
        .filter(|st| st.is_regular())
        .map(|st| st.size.max(0));
    let first = match known {
        Some(size) => (size.min(max).min(1 << 28) as usize).saturating_add(1),
        None => (max.min(CHUNK as i64 - 1) as usize) + 1,
    };
    let mut out = alloc::vec![0u8; first];
    let mut filled = 0usize;
    let waits = cancellable && stat.as_ref().is_some_and(sys::is_pollable);
    loop {
        if cancellable {
            poll_cancel();
        }
        if waits {
            wait_readable(fd);
        }
        let remaining = max - filled as i64;
        if filled == out.len() {
            // Full and not at the end: double, within the one byte past `max` that detects excess.
            let grown = (out.len() * 2)
                .max(CHUNK)
                .min((max as usize).saturating_add(1));
            out.resize(grown, 0);
        }
        let room = (out.len() - filled).min(LARGEST_READ);
        let want = if remaining < room as i64 {
            remaining as usize + 1
        } else {
            room
        };
        let n = match sys::read(fd, &mut out[filled..filled + want]) {
            Ok(n) => n,
            Err(_) => return Err(read_failure(false)),
        };
        if n as i64 > remaining {
            return Err(read_failure(true));
        }
        if n == 0 {
            out.truncate(filled);
            return Ok(out);
        }
        filled += n;
    }
}

pub fn read_file(path: &[u8], max: i64) -> Res<Vec<u8>> {
    #[cfg(not(test))]
    if !ms_rt::glue::pool::alone() {
        let ran =
            ms_rt::glue::pool::run_shielded(Lane::General, (path.to_vec(), max), &[], read_job);
        match ran {
            Offloaded::Done(result) => return result,
            Offloaded::NotRegular => {}
        }
    }
    let p = cpath(path)?;
    let fd = open_waitless(&p, sys::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", path))?;
    drop(p);
    let read = || {
        if let Ok(st) = sys::fstat(fd)
            && sys::is_dir(&st)
        {
            return Err(Fail::invalid());
        }
        read_bounded(fd, max)
    };
    // Cancellation abandons Rust frames, so the ordinary close below does not run. The pool
    // job above is shielded; this path can park on a pipe or device and needs runtime cleanup.
    #[cfg(not(test))]
    let result = ms_rt::fault::with_cleanup(
        &mut || {
            let _ = sys::close(fd);
        },
        read,
    );
    // Unit tests do not park and may run on threads; the cleanup stack belongs to the runtime.
    #[cfg(test)]
    let result = read();
    let _ = sys::close(fd);
    result
}

fn write_all(fd: sys::Fd, mut data: &[u8], path: &[u8], cancellable: bool) -> Res<()> {
    while !data.is_empty() {
        if cancellable {
            poll_cancel();
        }
        // A pool job cannot be cancelled, so it hands the kernel large writes; a cancellable
        // write stays in small steps so the check above runs between them.
        let end = data.len().min(if cancellable { 65536 } else { 1 << 20 });
        let n = sys::write(fd, &data[..end]).map_err(|e| Fail::errno(e, "write", path))?;
        if n == 0 {
            return Err(Fail::failed("short write"));
        }
        data = &data[n..];
    }
    Ok(())
}

fn write_with(path: &[u8], flags: i32, data: &[u8]) -> Res<()> {
    #[cfg(not(test))]
    if !ms_rt::glue::pool::alone() {
        match ms_rt::glue::pool::run_shielded(
            Lane::General,
            (path.to_vec(), flags),
            data,
            write_job,
        ) {
            Offloaded::Done(result) => return result,
            Offloaded::NotRegular => {}
        }
    }
    let p = cpath(path)?;
    let fd = sys::open(&p, sys::O_WRONLY | sys::O_CREAT | flags, 0o600)
        .map_err(|e| Fail::errno(e, "open", path))?;
    let written = write_all(fd, data, path, true);
    let closed = sys::close(fd).map_err(|e| Fail::errno(e, "close", path));
    written.and(closed)
}

pub fn write_file(path: &[u8], data: &[u8], replace: bool) -> Res<()> {
    write_with(path, if replace { sys::O_TRUNC } else { sys::O_EXCL }, data)
}

pub fn append_file(path: &[u8], data: &[u8]) -> Res<()> {
    write_with(path, sys::O_APPEND, data)
}

pub fn copy_file(source: &[u8], destination: &[u8], replace: bool, max: i64) -> Res<()> {
    cpath(source)?;
    cpath(destination)?;
    let data = read_file(source, max)?;
    write_file(destination, &data, replace)
}

// ---------------------------------------------------------------------------
// Whole-file calls on the blocking pool
// ---------------------------------------------------------------------------
//
// With other tasks to run, a whole-file read or write of a regular file runs on a blocking-pool
// thread, so the disk does not stall them. The wait is shielded: it ends only when the job
// does, which a regular file guarantees, so a write borrows the caller's bytes. The job opens
// (with `O_NONBLOCK` on Unix) and hands anything but a regular file back (a FIFO, a device, a
// directory), to run here on the runtime thread, where a wait is cancellable. Jobs never check for a stop
// request; it takes effect once the job is done.

#[cfg(not(test))]
use ms_rt::glue::pool::Lane;

/// What a whole-file job found.
#[cfg(not(test))]
enum Offloaded<T> {
    Done(Res<T>),
    /// Not a regular file: the call runs on the runtime thread instead.
    NotRegular,
}

/// Opens `path` for a job; `None` when it is not a regular file. Runs on a pool thread.
#[cfg(not(test))]
fn open_regular(path: &[u8], flags: i32) -> Option<Res<sys::Fd>> {
    let p = match cpath(path) {
        Ok(p) => p,
        Err(e) => return Some(Err(e)),
    };
    #[cfg(unix)]
    let flags = flags | libc::O_NONBLOCK;
    let fd = match sys::open(&p, flags, 0o600) {
        Ok(fd) => fd,
        // A FIFO without a reader.
        #[cfg(unix)]
        Err(libc::ENXIO) => return None,
        Err(e) => return Some(Err(Fail::errno(e, "open", path))),
    };
    if sys::fstat(fd).is_ok_and(|st| st.is_regular()) {
        return Some(Ok(fd));
    }
    let _ = sys::close(fd);
    None
}

#[cfg(not(test))]
fn read_job(job: &(Vec<u8>, i64), _: &[u8]) -> Offloaded<Vec<u8>> {
    let (path, max) = job;
    let fd = match open_regular(path, sys::O_RDONLY) {
        None => return Offloaded::NotRegular,
        Some(Err(e)) => return Offloaded::Done(Err(e)),
        Some(Ok(fd)) => fd,
    };
    let result = read_limited(fd, *max, false);
    let _ = sys::close(fd);
    Offloaded::Done(result)
}

#[cfg(not(test))]
fn write_job(job: &(Vec<u8>, i32), data: &[u8]) -> Offloaded<()> {
    let (path, flags) = job;
    let fd = match open_regular(path, sys::O_WRONLY | sys::O_CREAT | flags) {
        None => return Offloaded::NotRegular,
        Some(Err(e)) => return Offloaded::Done(Err(e)),
        Some(Ok(fd)) => fd,
    };
    let written = write_all(fd, data, path, false);
    let closed = sys::close(fd).map_err(|e| Fail::errno(e, "close", path));
    Offloaded::Done(written.and(closed))
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

pub fn info_of(st: &sys::Stat, name: &[u8]) -> Info {
    Info {
        name: name.to_vec(),
        size: st.size,
        mode: (st.mode & 0o177777) as i64,
        permissions: (st.mode & 0o7777) as i64,
        modified: nanos(st.modified),
        accessed: nanos(st.accessed),
        changed: nanos(st.changed),
        created: st.created.map(nanos),
        block_size: st.block_size,
        blocks: st.blocks,
        rdev: st.rdev,
        device: st.device,
        inode: st.inode,
        links: st.links,
        uid: st.uid,
        gid: st.gid,
    }
}

pub fn stat(path: &[u8], follow: bool) -> Res<Info> {
    offload(follow, path, |follow, path| stat_now(path, *follow))
}

fn stat_now(path: &[u8], follow: bool) -> Res<Info> {
    let p = cpath(path)?;
    let st = sys::stat(&p, follow)
        .map_err(|e| Fail::errno(e, if follow { "stat" } else { "lstat" }, path))?;
    Ok(info_of(&st, &lossy_name(&path::base(path))))
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
        Some(st) => (st.is_dir(), st.is_link()),
        None => (false, false),
    }
}

pub fn list(path: &[u8], max: i64) -> Res<Vec<Entry>> {
    offload(max, path, |max, path| list_now(path, *max))
}

fn list_now(path: &[u8], max: i64) -> Res<Vec<Entry>> {
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
        let (directory, symlink) = entry_kind(path, &name, kind);
        out.push(Entry {
            name: lossy_name(&name),
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

pub fn create_directory(path: &[u8], recursive: bool) -> Res<()> {
    offload(recursive, path, |recursive, path| {
        create_directory_now(path, *recursive)
    })
}

fn create_directory_now(path: &[u8], recursive: bool) -> Res<()> {
    let p = cpath(path)?;
    let made = if recursive {
        sys::mkdir_all(&p, 0o700)
    } else {
        sys::mkdir(&p, 0o700)
    };
    made.map_err(|e| Fail::errno(e, "mkdir", path))
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
    while p.len() > 1 && p.last().is_some_and(|&c| path::is_sep(c)) {
        p.pop();
    }
    let mut base = eval_symlinks(&cwd).map_err(|e| Fail::errno(e, "lstat", &cwd))?;
    let pc = CPath::new(&p).ok_or_else(Fail::invalid)?;
    let info = match sys::stat(&pc, false) {
        Err(e) if sys::is_not_found(e) => return Ok(p),
        Err(e) => return Err(Fail::errno(e, "lstat", &p)),
        Ok(st) => st,
    };
    if !sys::is_dir(&info) {
        return Ok(p);
    }
    loop {
        let bc = CPath::new(&base).ok_or_else(Fail::invalid)?;
        let ancestor = sys::stat(&bc, true).map_err(|e| Fail::errno(e, "stat", &base))?;
        if info.same_file(&ancestor) {
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

pub fn remove_tree(path: &[u8]) -> Res<()> {
    offload((), path, |_, path| remove_tree_now(path))
}

fn remove_tree_now(path: &[u8]) -> Res<()> {
    poll_cancel();
    let p = cpath(path)?;
    let st = match sys::stat(&p, false) {
        Err(e) if sys::is_not_found(e) => return Ok(()),
        Err(e) => return Err(Fail::errno(e, "lstat", path)),
        Ok(st) => st,
    };
    if !st.is_dir() {
        return sys::unlink(&p).map_err(|e| Fail::errno(e, "remove", path));
    }
    sys::remove_tree(&p).map_err(|e| Fail::errno(e, "remove", path))
}

pub fn remove(path: &[u8], recursive: bool) -> Res<()> {
    offload(recursive, path, |recursive, path| {
        remove_now(path, *recursive)
    })
}

fn remove_now(path: &[u8], recursive: bool) -> Res<()> {
    cpath(path)?;
    let p = removal_path(path)?;
    if recursive {
        return remove_tree(&p);
    }
    let c = cpath(&p)?;
    sys::remove(&c).map_err(|e| Fail::errno(e, "remove", &p))
}

pub fn rename(source: &[u8], destination: &[u8]) -> Res<()> {
    offload(destination.to_vec(), source, |destination, source| {
        rename_now(source, destination)
    })
}

fn rename_now(source: &[u8], destination: &[u8]) -> Res<()> {
    let (a, b) = (cpath(source)?, cpath(destination)?);
    sys::rename(&a, &b).map_err(|e| Fail::errno_paths(e, "rename", &[source, destination]))
}

pub fn read_link(path: &[u8]) -> Res<Vec<u8>> {
    offload((), path, |_, path| read_link_now(path))
}

fn read_link_now(path: &[u8]) -> Res<Vec<u8>> {
    let p = cpath(path)?;
    let target = sys::readlink(&p).map_err(|e| Fail::errno(e, "readlink", path))?;
    if !valid_utf8(&target) {
        return Err(Fail::status(STATUS_UNSUPPORTED));
    }
    Ok(target)
}

pub fn create_link(path: &[u8], target: &[u8]) -> Res<()> {
    offload(target.to_vec(), path, |target, path| {
        create_link_now(path, target)
    })
}

fn create_link_now(path: &[u8], target: &[u8]) -> Res<()> {
    let p = cpath(path)?;
    let t = cpath(target)?;
    sys::symlink(&t, &p).map_err(|e| Fail::errno_paths(e, "symlink", &[target, path]))
}

pub fn hard_link(source: &[u8], destination: &[u8]) -> Res<()> {
    offload(destination.to_vec(), source, |destination, source| {
        hard_link_now(source, destination)
    })
}

fn hard_link_now(source: &[u8], destination: &[u8]) -> Res<()> {
    let (a, b) = (cpath(source)?, cpath(destination)?);
    sys::link(&a, &b).map_err(|e| Fail::errno_paths(e, "link", &[source, destination]))
}

/// `filepath.EvalSymlinks`: the canonical form of an existing path, resolving every link.
pub fn eval_symlinks(original: &[u8]) -> Result<Vec<u8>, Errno> {
    sys::canonicalize(&CPath::new(original).ok_or(sys::EINVAL)?)
}

pub fn canonicalize(path: &[u8]) -> Res<Vec<u8>> {
    offload((), path, |_, path| canonicalize_now(path))
}

fn canonicalize_now(path: &[u8]) -> Res<Vec<u8>> {
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

/// `p` resolved against the working directory when relative (unchanged if that is unavailable).
pub fn absolute(p: &[u8]) -> Vec<u8> {
    if path::is_abs(p) {
        return p.to_vec();
    }
    match sys::getcwd() {
        Ok(cwd) => path::join(&cwd, p),
        Err(_) => p.to_vec(),
    }
}

/// The temporary directory as an absolute path, even when `$TMPDIR` is relative.
pub fn temporary_root() -> Vec<u8> {
    absolute(&sys::temp_dir())
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
    if !dir.last().is_some_and(|&c| path::is_sep(c)) {
        dir.push(path::SEP);
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
            Err(e) if sys::is_exists(e) => {
                tries += 1;
                if tries < 10000 {
                    continue;
                }
                return Err(Fail::errno(sys::EEXIST, "mkdirtemp", &name));
            }
            Err(e) => return Err(Fail::errno(e, "mkdir", &name)),
        }
    }
}

// ---------------------------------------------------------------------------
// Attributes
// ---------------------------------------------------------------------------

pub fn stat_filesystem(path: &[u8]) -> Res<sys::FsStat> {
    offload((), path, |_, path| stat_filesystem_now(path))
}

fn stat_filesystem_now(path: &[u8]) -> Res<sys::FsStat> {
    let p = cpath(path)?;
    sys::statfs(&p).map_err(|e| Fail::errno(e, "statfs", path))
}

pub fn chmod_link(path: &[u8], mode: i64) -> Res<()> {
    offload(mode, path, |v, path| chmod_link_now(path, *v))
}

fn chmod_link_now(path: &[u8], mode: i64) -> Res<()> {
    let c = cpath(path)?;
    if !(0..=0o7777).contains(&mode) {
        return Err(Fail::invalid());
    }
    sys::chmod_link(&c, mode as u32).map_err(|e| Fail::errno(e, "chmod", path))
}

pub fn access(path: &[u8], mode: i64) -> Res<()> {
    offload(mode, path, |v, path| access_now(path, *v))
}

fn access_now(path: &[u8], mode: i64) -> Res<()> {
    let p = cpath(path)?;
    if !(0..=7).contains(&mode) {
        return Err(Fail::invalid());
    }
    sys::access(&p, mode as i32).map_err(|e| Fail::errno(e, "access", path))
}

pub fn chmod(path: &[u8], mode: i64) -> Res<()> {
    offload(mode, path, |v, path| chmod_now(path, *v))
}

fn chmod_now(path: &[u8], mode: i64) -> Res<()> {
    let p = cpath(path)?;
    if !(0..=0o7777).contains(&mode) {
        return Err(Fail::invalid());
    }
    sys::chmod(&p, mode as u32).map_err(|e| Fail::errno(e, "chmod", path))
}

pub fn chown(path: &[u8], uid: i64, gid: i64, follow: bool) -> Res<()> {
    offload((uid, gid, follow), path, |&(uid, gid, follow), path| {
        chown_now(path, uid, gid, follow)
    })
}

fn chown_now(path: &[u8], uid: i64, gid: i64, follow: bool) -> Res<()> {
    let p = cpath(path)?;
    if uid < -1 || gid < -1 || uid > 2_147_483_647 || gid > 2_147_483_647 {
        return Err(Fail::invalid());
    }
    sys::chown(&p, uid, gid, follow)
        .map_err(|e| Fail::errno(e, if follow { "chown" } else { "lchown" }, path))
}

pub fn truncate(path: &[u8], size: i64) -> Res<()> {
    offload(size, path, |v, path| truncate_now(path, *v))
}

fn truncate_now(path: &[u8], size: i64) -> Res<()> {
    let p = cpath(path)?;
    if size < 0 {
        return Err(Fail::invalid());
    }
    sys::truncate(&p, size).map_err(|e| Fail::errno(e, "truncate", path))
}

pub fn set_times(path: &[u8], accessed: (i64, i64), modified: (i64, i64), follow: bool) -> Res<()> {
    offload(
        (accessed, modified, follow),
        path,
        |&(accessed, modified, follow), path| set_times_now(path, accessed, modified, follow),
    )
}

fn set_times_now(path: &[u8], accessed: (i64, i64), modified: (i64, i64), follow: bool) -> Res<()> {
    let p = cpath(path)?;
    sys::utimens(&p, accessed, modified, follow).map_err(|e| Fail::errno(e, "chtimes", path))
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::string::String;
    #[cfg_attr(windows, allow(unused_imports))]
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

    #[cfg(unix)]
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

    #[cfg(unix)]
    #[test]
    fn a_name_that_is_not_utf8_is_listed_lossily() {
        let root = scratch("l");
        create_directory(&root, true).unwrap();
        write_file(&sub(&root, "a.txt"), b"a", false).unwrap();
        let created = write_file(&path::join(&root, b"bad\xff.dat"), b"x", false);
        if cfg!(target_os = "macos") {
            // APFS only holds valid UTF-8 names, so the file cannot exist to be listed.
            assert_eq!(created.unwrap_err().status, ms_rt_abi::STATUS_FAILED);
            remove(&root, true).unwrap();
            return;
        }
        created.unwrap();
        let names: Vec<Vec<u8>> = list(&root, UNLIMITED)
            .unwrap()
            .into_iter()
            .map(|e| e.name)
            .collect();
        assert_eq!(
            names,
            [b"a.txt".to_vec(), "bad\u{fffd}.dat".as_bytes().to_vec()]
        );
        remove(&root, true).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn stat_and_glob_report_a_non_utf8_name_lossily() {
        let root = scratch("s");
        create_directory(&root, true).unwrap();
        let bad = path::join(&root, b"bad\xff.dat");
        let created = write_file(&bad, b"x", false);
        if cfg!(target_os = "macos") {
            // APFS only holds valid UTF-8 names, so the file cannot exist to be listed.
            assert_eq!(created.unwrap_err().status, ms_rt_abi::STATUS_FAILED);
            remove(&root, true).unwrap();
            return;
        }
        created.unwrap();
        assert_eq!(
            stat(&bad, true).unwrap().name,
            "bad\u{fffd}.dat".as_bytes().to_vec()
        );
        let found = crate::walk::glob(&root, b"*.dat", UNLIMITED).unwrap();
        assert_eq!(found, ["bad\u{fffd}.dat".as_bytes().to_vec()]);
        remove(&root, true).unwrap();
    }

    #[cfg(unix)]
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

    #[cfg(unix)]
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

    #[cfg(unix)]
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
        // Linux cannot change a link's own mode; macOS can.
        if cfg!(target_os = "linux") {
            assert_eq!(
                chmod_link(&f, 0o600).unwrap_err().status,
                STATUS_UNSUPPORTED
            );
        } else {
            chmod_link(&f, 0o600).unwrap();
        }
        assert!(stat_filesystem(&root).unwrap().block_size > 0);
        remove(&path::dir(&root), true).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn files_round_trip_on_windows() {
        let root = scratch("w");
        create_directory(&root, true).unwrap();
        let f = sub(&root, "f.txt");
        write_file(&f, b"hello", false).unwrap();
        assert_eq!(
            write_file(&f, b"x", false).unwrap_err().status,
            STATUS_ALREADY_EXISTS
        );
        append_file(&f, b"!").unwrap();
        assert_eq!(read_file(&f, UNLIMITED).unwrap(), b"hello!");
        assert_eq!(read_file(&f, 2).unwrap_err().status, STATUS_LIMIT_EXCEEDED);
        assert_eq!(
            read_file(&sub(&root, "none"), UNLIMITED)
                .unwrap_err()
                .status,
            STATUS_NOT_FOUND
        );
        let info = stat(&f, true).unwrap();
        assert_eq!(
            (info.size, info.kinds(), info.permissions),
            (6, KIND_REGULAR, 0o666)
        );
        chmod(&f, 0o444).unwrap();
        assert_eq!(stat(&f, true).unwrap().permissions, 0o444);
        assert_eq!(
            chown(&f, 1, 1, true).unwrap_err().status,
            STATUS_UNSUPPORTED
        );
        copy_file(&f, &sub(&root, "g"), false, UNLIMITED).unwrap();
        rename(&sub(&root, "g"), &sub(&root, "h")).unwrap();
        let names: Vec<String> = list(&root, UNLIMITED)
            .unwrap()
            .iter()
            .map(|e| String::from_utf8(e.name.clone()).unwrap())
            .collect();
        assert_eq!(names, ["f.txt", "h"]);
        assert_eq!(remove(&root, false).unwrap_err().status, STATUS_NOT_EMPTY);
        // Read-only files are removed too.
        remove(&root, true).unwrap();
        assert_eq!(stat(&root, true).unwrap_err().status, STATUS_NOT_FOUND);
        let _ = remove(&path::dir(&root), true);
    }
}
