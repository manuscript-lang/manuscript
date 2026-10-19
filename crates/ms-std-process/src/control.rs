//! Process-wide controls, ported from `osProcessControl` in `pkg/runtime/process.go`.
use crate::envfile;
use alloc::string::String;
use alloc::vec::Vec;
use core::ffi::CStr;
use ms_rt_abi::{STATUS_INVALID_DATA, STATUS_LIMIT_EXCEEDED, STATUS_UNSUPPORTED};
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::ops::read_bounded;
use ms_std_fs::sys::{self, CPath};

/// The group id type `getgrouplist` takes: `int` on macOS, `gid_t` elsewhere.
#[cfg(target_os = "macos")]
type GroupId = libc::c_int;
#[cfg(not(target_os = "macos"))]
type GroupId = libc::gid_t;

fn utf8(bytes: Vec<u8>) -> Res<Vec<u8>> {
    match core::str::from_utf8(&bytes) {
        Ok(_) => Ok(bytes),
        Err(_) => Err(Fail::status(STATUS_UNSUPPORTED)),
    }
}

fn nul_free(bytes: &[u8]) -> bool {
    !bytes.contains(&0)
}

pub fn working_directory() -> Res<Vec<u8>> {
    let cwd = sys::getcwd().map_err(|e| Fail::errno(e, "getwd", b""))?;
    utf8(cwd)
}

pub fn change_directory(path: &[u8]) -> Res<()> {
    let p = CPath::new(path).ok_or_else(Fail::invalid)?;
    // SAFETY: `p` is NUL-terminated.
    if unsafe { libc::chdir(p.as_ptr()) } != 0 {
        return Err(Fail::errno(sys::errno(), "chdir", path));
    }
    Ok(())
}

pub fn send_signal(pid: i64, signal: i64) -> Res<()> {
    if !(-2_147_483_648..=2_147_483_647).contains(&pid) || !(0..=64).contains(&signal) {
        return Err(Fail::invalid());
    }
    // SAFETY: plain system call.
    if unsafe { libc::kill(pid as libc::pid_t, signal as i32) } != 0 {
        return Err(Fail::raw(sys::errno()));
    }
    Ok(())
}

pub fn groups() -> Res<Vec<i64>> {
    // SAFETY: a zero-sized query returns the group count.
    let n = unsafe { libc::getgroups(0, core::ptr::null_mut()) };
    if n < 0 {
        return Err(Fail::raw(sys::errno()));
    }
    let mut list: Vec<libc::gid_t> = alloc::vec![0; n as usize];
    // SAFETY: `list` has room for `n` entries.
    let got = unsafe { libc::getgroups(n, list.as_mut_ptr()) };
    if got < 0 {
        return Err(Fail::raw(sys::errno()));
    }
    Ok(list[..got as usize].iter().map(|&g| g as i64).collect())
}

pub fn umask(mask: i64) -> Res<i64> {
    if !(0..=0o777).contains(&mask) {
        return Err(Fail::invalid());
    }
    // SAFETY: plain system call.
    Ok(unsafe { libc::umask(mask as libc::mode_t) } as i64)
}

pub fn set_identity(kind: &[u8], id: i64) -> Res<()> {
    if !(0..=2_147_483_647).contains(&id) {
        return Err(Fail::invalid());
    }
    let id = id as u32;
    // SAFETY: plain system calls.
    let r = unsafe {
        match kind {
            b"uid" => libc::setuid(id),
            b"gid" => libc::setgid(id),
            b"euid" => libc::seteuid(id),
            b"egid" => libc::setegid(id),
            _ => return Err(Fail::invalid()),
        }
    };
    if r != 0 {
        return Err(Fail::raw(sys::errno()));
    }
    Ok(())
}

pub fn set_groups(groups: &[i64]) -> Res<()> {
    if groups.iter().any(|g| !(0..=2_147_483_647).contains(g)) {
        return Err(Fail::invalid());
    }
    apply_groups(groups)
}

fn apply_groups(groups: &[i64]) -> Res<()> {
    let list: Vec<libc::gid_t> = groups.iter().map(|&g| g as libc::gid_t).collect();
    // SAFETY: `list` is readable for its length.
    if unsafe { libc::setgroups(list.len() as _, list.as_ptr()) } != 0 {
        return Err(Fail::raw(sys::errno()));
    }
    Ok(())
}

/// `initialize_groups`: the groups of `username` with `gid` first.
pub fn initialize_groups(username: &[u8], gid: i64) -> Res<()> {
    if !(0..=2_147_483_647).contains(&gid) || !nul_free(username) {
        return Err(Fail::invalid());
    }
    let name = CPath::new(username).ok_or_else(Fail::invalid)?;
    // SAFETY: `name` is NUL-terminated.
    let pw = unsafe { libc::getpwnam(name.as_ptr()) };
    if pw.is_null() {
        let mut m = b"user: unknown user ".to_vec();
        m.extend_from_slice(username);
        return Err(Fail {
            status: ms_rt_abi::STATUS_FAILED,
            message: Some(m),
        });
    }
    // SAFETY: `pw` is a valid passwd record.
    let primary: GroupId = unsafe { (*pw).pw_gid } as _;
    let mut count: libc::c_int = 32;
    let mut ids: Vec<GroupId> = alloc::vec![0; count as usize];
    loop {
        // SAFETY: `ids` has room for `count` entries.
        let r = unsafe { libc::getgrouplist(name.as_ptr(), primary, ids.as_mut_ptr(), &mut count) };
        if r >= 0 {
            break;
        }
        ids.resize(count.max(ids.len() as i32 * 2) as usize, 0);
        count = ids.len() as libc::c_int;
    }
    let mut groups: Vec<i64> = alloc::vec![gid];
    for &id in &ids[..count as usize] {
        if !groups.contains(&(id as i64)) {
            groups.push(id as i64);
        }
    }
    apply_groups(&groups)
}

/// Process title through procfs, as Go's `hostos` does on Linux.
#[cfg(target_os = "linux")]
fn comm_path() -> CPath {
    // SAFETY: plain system call.
    let pid = unsafe { libc::getpid() };
    let text = alloc::format!("/proc/self/task/{pid}/comm");
    CPath::new(text.as_bytes()).expect("no NUL in a formatted path")
}

#[cfg(target_os = "linux")]
pub fn title() -> Res<Vec<u8>> {
    let p = comm_path();
    let fd = sys::open(&p, libc::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", p.bytes()))?;
    let data = read_bounded(fd, 4096);
    let _ = sys::close(fd);
    let mut data = data?;
    if data.last() == Some(&b'\n') {
        data.pop();
    }
    utf8(data)
}

#[cfg(not(target_os = "linux"))]
pub fn title() -> Res<Vec<u8>> {
    Err(Fail::status(STATUS_UNSUPPORTED))
}

#[cfg(target_os = "linux")]
pub fn set_title(title: &[u8]) -> Res<()> {
    if title.contains(&0) || title.contains(&b'\n') {
        return Err(Fail::invalid());
    }
    if title.len() > 15 {
        return Err(Fail::errno(libc::ENAMETOOLONG, "write", b""));
    }
    let p = comm_path();
    let fd = sys::open(&p, libc::O_WRONLY | libc::O_TRUNC, 0o600)
        .map_err(|e| Fail::errno(e, "open", p.bytes()))?;
    let r = sys::write(fd, title).map_err(|e| Fail::errno(e, "write", p.bytes()));
    let _ = sys::close(fd);
    r.map(|_| ())
}

#[cfg(not(target_os = "linux"))]
pub fn set_title(title: &[u8]) -> Res<()> {
    if title.contains(&0) || title.contains(&b'\n') {
        return Err(Fail::invalid());
    }
    Err(Fail::status(STATUS_UNSUPPORTED))
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

/// The live environment as `(name, value)` pairs; any non-UTF-8 entry is `Unsupported`.
pub fn environment() -> Res<Vec<(Vec<u8>, Vec<u8>)>> {
    let mut out = Vec::new();
    // SAFETY: `environ` is a NULL-terminated array of C strings.
    unsafe {
        let mut p = environ;
        while !(*p).is_null() {
            let entry = CStr::from_ptr(*p).to_bytes();
            if core::str::from_utf8(entry).is_err() {
                return Err(Fail::status(STATUS_UNSUPPORTED));
            }
            if let Some(at) = entry.iter().position(|&c| c == b'=') {
                out.push((entry[..at].to_vec(), entry[at + 1..].to_vec()));
            }
            p = p.add(1);
        }
    }
    Ok(out)
}

unsafe extern "C" {
    static environ: *const *const libc::c_char;
}

pub fn set_environment(name: &[u8], value: Option<&[u8]>) -> Res<()> {
    if name.is_empty() || name.contains(&b'=') || name.contains(&0) {
        return Err(Fail::invalid());
    }
    let n = CPath::new(name).ok_or_else(Fail::invalid)?;
    match value {
        Some(v) => {
            let v = CPath::new(v).ok_or_else(Fail::invalid)?;
            // SAFETY: both strings are NUL-terminated.
            if unsafe { libc::setenv(n.as_ptr(), v.as_ptr(), 1) } != 0 {
                return Err(Fail::errno(sys::errno(), "setenv", name));
            }
        }
        None => {
            // SAFETY: `n` is NUL-terminated.
            if unsafe { libc::unsetenv(n.as_ptr()) } != 0 {
                return Err(Fail::errno(sys::errno(), "unsetenv", name));
            }
        }
    }
    Ok(())
}

pub fn load_environment(path: &[u8], max: i64) -> Res<()> {
    let p = CPath::new(path).ok_or_else(Fail::invalid)?;
    let fd = sys::open(&p, libc::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", path))?;
    let data = read_bounded(fd, max);
    let _ = sys::close(fd);
    let data = match data {
        Ok(d) => d,
        // `readBounded`'s own codes: a read error is InvalidData here, a stall is a bare Failed.
        Err(f) if f.status == STATUS_LIMIT_EXCEEDED => return Err(f),
        Err(_) => return Err(Fail::status(STATUS_INVALID_DATA)),
    };
    let text = core::str::from_utf8(&data).map_err(|_| Fail::status(STATUS_INVALID_DATA))?;
    let entries = envfile::parse(text).ok_or_else(|| Fail::status(STATUS_INVALID_DATA))?;
    for (key, value) in entries {
        let k = CPath::new(key.as_bytes()).ok_or_else(Fail::invalid)?;
        // SAFETY: `k` is NUL-terminated.
        if unsafe { libc::getenv(k.as_ptr()) }.is_null() {
            set_environment(key.as_bytes(), Some(value.as_bytes()))?;
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Information
// ---------------------------------------------------------------------------

pub struct Usage {
    pub user_us: i64,
    pub system_us: i64,
    pub max_rss: i64,
    pub minor_faults: i64,
    pub major_faults: i64,
    pub reads: i64,
    pub writes: i64,
    pub voluntary: i64,
    pub involuntary: i64,
}

pub fn resource_usage() -> Res<Usage> {
    // SAFETY: zeroed `rusage` is a valid out buffer.
    let mut r: libc::rusage = unsafe { core::mem::zeroed() };
    // SAFETY: `r` is writable.
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut r) } != 0 {
        return Err(Fail::raw(sys::errno()));
    }
    let rss = if cfg!(target_os = "linux") {
        r.ru_maxrss as i64 * 1024
    } else {
        r.ru_maxrss as i64
    };
    Ok(Usage {
        user_us: r.ru_utime.tv_sec as i64 * 1_000_000 + r.ru_utime.tv_usec as i64,
        system_us: r.ru_stime.tv_sec as i64 * 1_000_000 + r.ru_stime.tv_usec as i64,
        max_rss: rss,
        minor_faults: r.ru_minflt as i64,
        major_faults: r.ru_majflt as i64,
        reads: r.ru_inblock as i64,
        writes: r.ru_oublock as i64,
        voluntary: r.ru_nvcsw as i64,
        involuntary: r.ru_nivcsw as i64,
    })
}

pub struct Info {
    pub pid: i64,
    pub parent_pid: i64,
    pub executable: Vec<u8>,
    pub uid: i64,
    pub gid: i64,
    pub effective_uid: i64,
    pub effective_gid: i64,
}

pub fn info() -> Res<Info> {
    #[cfg(target_os = "linux")]
    let executable = {
        let p = CPath::new(b"/proc/self/exe").expect("no NUL");
        sys::readlink(&p).map_err(|e| Fail::errno(e, "readlink", b"/proc/self/exe"))?
    };
    #[cfg(not(target_os = "linux"))]
    let executable = Vec::new();
    let executable = utf8(executable)?;
    // SAFETY: plain system calls.
    unsafe {
        Ok(Info {
            pid: libc::getpid() as i64,
            parent_pid: libc::getppid() as i64,
            executable,
            uid: libc::getuid() as i64,
            gid: libc::getgid() as i64,
            effective_uid: libc::geteuid() as i64,
            effective_gid: libc::getegid() as i64,
        })
    }
}

pub const OS: &str = if cfg!(target_os = "macos") {
    "darwin"
} else {
    "linux"
};
pub const ARCH: &str = if cfg!(target_arch = "aarch64") {
    "arm64"
} else {
    "amd64"
};

/// `memoryLimit`: the cgroup memory limit and current use of this process, `(0, 0)` when unlimited.
#[cfg(target_os = "linux")]
pub fn memory_limit() -> Res<(i64, i64)> {
    fn read_text(path: &[u8]) -> Result<Option<String>, Fail> {
        let p = CPath::new(path).ok_or_else(Fail::invalid)?;
        let fd = match sys::open(&p, libc::O_RDONLY, 0) {
            Ok(fd) => fd,
            Err(libc::ENOENT) => return Ok(None),
            Err(e) => return Err(Fail::errno(e, "open", path)),
        };
        let data = read_bounded(fd, 1 << 20);
        let _ = sys::close(fd);
        Ok(Some(String::from_utf8_lossy(&data?).into_owned()))
    }
    let cgroups = match read_text(b"/proc/self/cgroup")? {
        Some(t) => t,
        None => return Err(Fail::errno(libc::ENOENT, "open", b"/proc/self/cgroup")),
    };
    for line in cgroups.split('\n') {
        let mut parts = line.splitn(3, ':');
        let (Some(hier), Some(ctrl), Some(rel)) = (parts.next(), parts.next(), parts.next()) else {
            continue;
        };
        let (mut base, mut limit_file, mut current_file) = ("", "memory.max", "memory.current");
        if hier == "0" && ctrl.is_empty() {
            base = "/sys/fs/cgroup";
        } else if ctrl.split(',').any(|c| c == "memory") {
            base = "/sys/fs/cgroup/memory";
            limit_file = "memory.limit_in_bytes";
            current_file = "memory.usage_in_bytes";
        }
        if base.is_empty() {
            continue;
        }
        let rel = ms_std_fs::path::clean(alloc::format!("/{rel}").as_bytes());
        let mut dir = Vec::from(base.as_bytes());
        dir.extend_from_slice(&rel);
        if rel == b"/" {
            dir.pop();
        }
        let file = |name: &str| {
            let mut p = dir.clone();
            p.push(b'/');
            p.extend_from_slice(name.as_bytes());
            p
        };
        let Some(limit_text) = read_text(&file(limit_file))? else {
            return Ok((0, 0));
        };
        let limit_text = limit_text.trim();
        if limit_text == "max" {
            return Ok((0, 0));
        }
        let limit: i64 = match limit_text.parse() {
            Ok(v) if v >= 0 => v,
            _ => return Err(Fail::failed("invalid cgroup memory limit")),
        };
        if limit >= 1 << 60 {
            return Ok((0, 0));
        }
        let Some(current_text) = read_text(&file(current_file))? else {
            return Err(Fail::errno(libc::ENOENT, "open", &file(current_file)));
        };
        let current: i64 = match current_text.trim().parse() {
            Ok(v) if v >= 0 => v,
            _ => return Err(Fail::failed("invalid cgroup memory usage")),
        };
        return Ok((limit, current));
    }
    Ok((0, 0))
}

#[cfg(not(target_os = "linux"))]
pub fn memory_limit() -> Res<(i64, i64)> {
    Ok((0, 0))
}

/// Bytes the host reports as available to new allocations (`MemAvailable`).
#[cfg(target_os = "linux")]
pub fn host_available_memory() -> Res<i64> {
    let p = CPath::new(b"/proc/meminfo").expect("no NUL");
    let fd =
        sys::open(&p, libc::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", b"/proc/meminfo"))?;
    let data = read_bounded(fd, 1 << 20);
    let _ = sys::close(fd);
    let text = String::from_utf8_lossy(&data?).into_owned();
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("MemAvailable:") {
            let kb: i64 = rest
                .trim()
                .trim_end_matches("kB")
                .trim()
                .parse()
                .map_err(|_| Fail::failed("invalid /proc/meminfo"))?;
            return Ok(kb.saturating_mul(1024));
        }
    }
    Err(Fail::failed("MemAvailable missing from /proc/meminfo"))
}

#[cfg(not(target_os = "linux"))]
pub fn host_available_memory() -> Res<i64> {
    Err(Fail::status(STATUS_UNSUPPORTED))
}

pub fn available_memory() -> Res<i64> {
    let (limit, current) = memory_limit()?;
    let available = host_available_memory()?;
    Ok(if limit > 0 {
        available.min((limit - current).max(0))
    } else {
        available
    })
}

/// Resident set size in bytes (`/proc/self/statm`).
#[cfg(target_os = "linux")]
pub fn resident_bytes() -> Res<i64> {
    let p = CPath::new(b"/proc/self/statm").expect("no NUL");
    let fd = sys::open(&p, libc::O_RDONLY, 0)
        .map_err(|e| Fail::errno(e, "open", b"/proc/self/statm"))?;
    let data = read_bounded(fd, 4096);
    let _ = sys::close(fd);
    let text = String::from_utf8_lossy(&data?).into_owned();
    let pages: i64 = text
        .split_whitespace()
        .nth(1)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| Fail::failed("invalid /proc/self/statm"))?;
    // SAFETY: plain call.
    let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) } as i64;
    Ok(pages * page)
}

#[cfg(not(target_os = "linux"))]
pub fn resident_bytes() -> Res<i64> {
    Err(Fail::status(STATUS_UNSUPPORTED))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn environment_round_trip() {
        let _guard = crate::environment_guard();
        set_environment(b"MS_PROC_TEST", Some(b"v1")).unwrap();
        assert!(
            environment()
                .unwrap()
                .contains(&(b"MS_PROC_TEST".to_vec(), b"v1".to_vec()))
        );
        set_environment(b"MS_PROC_TEST", None).unwrap();
        assert!(
            !environment()
                .unwrap()
                .iter()
                .any(|(k, _)| k == b"MS_PROC_TEST")
        );
        assert!(set_environment(b"", Some(b"x")).is_err());
        assert!(set_environment(b"A=B", None).is_err());
    }

    #[test]
    fn load_environment_keeps_existing_values() {
        let _guard = crate::environment_guard();
        let path = alloc::format!("/tmp/msproc-env-{}", info().unwrap().pid);
        ms_std_fs::ops::write_file(path.as_bytes(), b"MS_LOAD_A=1\nMS_LOAD_B='two'\n", true)
            .unwrap();
        set_environment(b"MS_LOAD_A", Some(b"kept")).unwrap();
        set_environment(b"MS_LOAD_B", None).unwrap();
        load_environment(path.as_bytes(), i64::MAX).unwrap();
        let env = environment().unwrap();
        assert!(env.contains(&(b"MS_LOAD_A".to_vec(), b"kept".to_vec())));
        assert!(env.contains(&(b"MS_LOAD_B".to_vec(), b"two".to_vec())));
        assert_eq!(
            load_environment(path.as_bytes(), 3).unwrap_err().status,
            STATUS_LIMIT_EXCEEDED
        );
        ms_std_fs::ops::write_file(path.as_bytes(), b"bad line", true).unwrap();
        assert_eq!(
            load_environment(path.as_bytes(), i64::MAX)
                .unwrap_err()
                .status,
            STATUS_INVALID_DATA
        );
        let _ = ms_std_fs::ops::remove(path.as_bytes(), false);
    }

    #[test]
    fn identity_and_usage() {
        let i = info().unwrap();
        assert!(i.pid > 0 && i.executable.starts_with(b"/"));
        assert!(resource_usage().unwrap().max_rss > 0);
        assert_eq!(umask(0o022).map(|_| ()), Ok(()));
        assert_eq!(
            umask(0o1000).unwrap_err().status,
            ms_rt_abi::STATUS_INVALID_INPUT
        );
        assert_eq!(send_signal(i.pid, 0), Ok(()));
        assert_eq!(
            send_signal(0, 65).unwrap_err().status,
            ms_rt_abi::STATUS_INVALID_INPUT
        );
        assert!(!working_directory().unwrap().is_empty());
        assert!(resident_bytes().unwrap() > 0);
        assert!(available_memory().unwrap() > 0);
        assert_eq!(
            set_identity(b"nope", 0).unwrap_err().status,
            ms_rt_abi::STATUS_INVALID_INPUT
        );
    }
}

unsafe extern "C-unwind" {
    /// Small-block heap bytes `[used, in_use]` from the runtime allocator.
    fn msrt_heap_stats(out: *mut i64);
}

/// Heap and resident bytes: `(heap_used, heap_total, heap_system, external, resident)`.
pub fn memory_usage() -> Res<[i64; 5]> {
    let mut heap = [0i64; 2];
    // SAFETY: `heap` holds the two words the runtime writes.
    unsafe { msrt_heap_stats(heap.as_mut_ptr()) };
    let resident = resident_bytes()?;
    Ok([
        heap[0],
        heap[1],
        heap[1],
        (resident - heap[1]).max(0),
        resident,
    ])
}
