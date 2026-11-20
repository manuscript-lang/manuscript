//! Process-wide controls.
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_FAILED, STATUS_UNSUPPORTED};

/// A failed query: the status and, for `STATUS_FAILED`, the text.
#[derive(Debug, PartialEq, Eq)]
pub struct Fail {
    pub status: u8,
    pub message: Option<String>,
}

pub type Res<T> = Result<T, Fail>;

impl Fail {
    pub fn status(status: u8) -> Fail {
        Fail {
            status,
            message: None,
        }
    }

    pub fn failed(message: &str) -> Fail {
        Fail {
            status: STATUS_FAILED,
            message: Some(message.into()),
        }
    }

    /// A failed operating-system call of `op` with the error text of `e`.
    pub fn os(op: &str, e: &std::io::Error) -> Fail {
        Fail::failed(&alloc::format!("{op}: {e}"))
    }
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

/// The live environment as `(name, value)` pairs; any non-UTF-8 entry is `Unsupported`.
/// The live environment as bytes. An entry whose name or value is not valid UTF-8 cannot be a
/// `String` and is left out, so one such variable does not hide the rest (`PATH`, the test
/// runner's own settings).
pub fn environment() -> Res<Vec<(Vec<u8>, Vec<u8>)>> {
    let mut out = Vec::new();
    for (name, value) in std::env::vars_os() {
        let (Some(name), Some(value)) = (name.to_str(), value.to_str()) else {
            continue;
        };
        out.push((name.as_bytes().to_vec(), value.as_bytes().to_vec()));
    }
    Ok(out)
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

/// The path of the running executable.
pub(crate) fn executable() -> Res<Vec<u8>> {
    let path = std::env::current_exe().map_err(|e| Fail::os("executable", &e))?;
    let text = path
        .into_os_string()
        .into_string()
        .map_err(|_| Fail::status(STATUS_UNSUPPORTED))?;
    Ok(text.into_bytes())
}

#[cfg(unix)]
pub fn info() -> Res<Info> {
    // SAFETY: plain system calls.
    unsafe {
        Ok(Info {
            pid: std::process::id() as i64,
            parent_pid: std::os::unix::process::parent_id() as i64,
            executable: executable()?,
            uid: libc::getuid() as i64,
            gid: libc::getgid() as i64,
            effective_uid: libc::geteuid() as i64,
            effective_gid: libc::getegid() as i64,
        })
    }
}

pub const OS: &str = if cfg!(target_os = "macos") {
    "darwin"
} else if cfg!(windows) {
    "windows"
} else {
    "linux"
};
pub const ARCH: &str = if cfg!(target_arch = "aarch64") {
    "arm64"
} else {
    "amd64"
};

/// Resident set size in bytes (`/proc/self/statm`).
#[cfg(target_os = "linux")]
pub fn resident_bytes() -> Res<i64> {
    let text = std::fs::read_to_string("/proc/self/statm")
        .map_err(|e| Fail::os("open /proc/self/statm", &e))?;
    let pages: i64 = text
        .split_whitespace()
        .nth(1)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| Fail::failed("invalid /proc/self/statm"))?;
    // SAFETY: plain call.
    let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) } as i64;
    Ok(pages * page)
}

/// Resident set size in bytes (`proc_pidinfo` task info).
#[cfg(target_os = "macos")]
pub fn resident_bytes() -> Res<i64> {
    // SAFETY: a zeroed `proc_taskinfo` is a valid out buffer.
    let mut info: libc::proc_taskinfo = unsafe { core::mem::zeroed() };
    let size = core::mem::size_of::<libc::proc_taskinfo>() as libc::c_int;
    // SAFETY: `info` is writable for `size` bytes.
    let got = unsafe {
        libc::proc_pidinfo(
            std::process::id() as libc::c_int,
            libc::PROC_PIDTASKINFO,
            0,
            (&mut info as *mut libc::proc_taskinfo).cast(),
            size,
        )
    };
    if got != size {
        return Err(Fail::failed("proc_pidinfo failed"));
    }
    Ok(info.pti_resident_size as i64)
}

#[cfg(all(unix, not(any(target_os = "linux", target_os = "macos"))))]
pub fn resident_bytes() -> Res<i64> {
    Err(Fail::status(STATUS_UNSUPPORTED))
}

#[cfg(windows)]
pub use crate::control_windows::*;

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn identity_and_usage() {
        let i = info().unwrap();
        assert!(i.pid > 0 && i.executable.starts_with(b"/"));
        if cfg!(any(target_os = "linux", target_os = "macos")) {
            assert!(resident_bytes().unwrap() > 0);
            assert!(memory_usage().unwrap()[4] > 0);
        } else {
            assert_eq!(
                resident_bytes().unwrap_err().status,
                ms_rt_abi::STATUS_UNSUPPORTED
            );
        }
    }
}

use ms_rt::obj::msrt_heap_stats;

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

#[cfg(test)]
mod non_utf8_environment {
    use super::*;

    #[cfg(unix)]
    fn invalid_text() -> std::ffi::OsString {
        std::os::unix::ffi::OsStringExt::from_vec(vec![b'a', 0xff, 0xfe])
    }

    #[cfg(windows)]
    fn invalid_text() -> std::ffi::OsString {
        std::os::windows::ffi::OsStringExt::from_wide(&[0x61, 0xd800])
    }

    /// One variable that is not valid UTF-8 is left out; the others stay readable.
    #[test]
    fn environment_skips_entries_that_are_not_utf8() {
        #[cfg(unix)]
        let _guard = crate::environment_guard();
        let bad = "MS_PROC_TEST_NON_UTF8";
        // SAFETY: tests that touch the environment on Unix hold the environment guard.
        unsafe {
            std::env::set_var("MS_PROC_TEST_UTF8", "ok");
            std::env::set_var(bad, invalid_text());
        }
        let entries = environment().unwrap();
        // SAFETY: as above.
        unsafe {
            std::env::remove_var(bad);
            std::env::remove_var("MS_PROC_TEST_UTF8");
        }
        assert!(entries.contains(&(b"MS_PROC_TEST_UTF8".to_vec(), b"ok".to_vec())));
        assert!(!entries.iter().any(|(name, _)| name == bad.as_bytes()));
    }
}
