//! Process-wide controls on Windows, following `hostos` and `os` in Go: there are no user or group
//! ids, no umask, no `exec`, and signals are `TerminateProcess`.
use crate::control::{Info, Usage};
use alloc::string::String;
use alloc::vec::Vec;
use core::cell::UnsafeCell;
use core::ptr::{null, null_mut};
use core::sync::atomic::{AtomicBool, Ordering};
use ms_rt_abi::{STATUS_NOT_FOUND, STATUS_UNSUPPORTED};
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys::{self, CPath};
use windows_sys::Win32::Foundation::{
    CloseHandle, ERROR_INVALID_HANDLE, FILETIME, GetLastError, HANDLE,
};
use windows_sys::Win32::System::Console::{GetConsoleTitleW, SetConsoleTitleW};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::Environment::{
    FreeEnvironmentStringsW, GetEnvironmentStringsW, SetCurrentDirectoryW, SetEnvironmentVariableW,
};
use windows_sys::Win32::System::LibraryLoader::GetModuleFileNameW;
use windows_sys::Win32::System::ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS};
use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};
use windows_sys::Win32::System::Threading::{
    GetCurrentProcess, GetCurrentProcessId, GetExitCodeProcess, GetProcessIoCounters,
    GetProcessTimes, IO_COUNTERS, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
    PROCESS_TERMINATE, TerminateProcess,
};

fn utf8(bytes: Vec<u8>) -> Res<Vec<u8>> {
    match core::str::from_utf8(&bytes) {
        Ok(_) => Ok(bytes),
        Err(_) => Err(Fail::status(STATUS_UNSUPPORTED)),
    }
}

fn wide(bytes: &[u8]) -> Option<Vec<u16>> {
    let text = core::str::from_utf8(bytes).ok()?;
    let mut w: Vec<u16> = text.encode_utf16().collect();
    w.push(0);
    Some(w)
}

fn narrow(w: &[u16]) -> Vec<u8> {
    String::from_utf16_lossy(w).into_bytes()
}

pub fn working_directory() -> Res<Vec<u8>> {
    let cwd = sys::getcwd().map_err(|e| Fail::errno(e, "getwd", b""))?;
    utf8(cwd)
}

pub fn change_directory(path: &[u8]) -> Res<()> {
    CPath::new(path).ok_or_else(Fail::invalid)?;
    let w = wide(path).ok_or_else(Fail::invalid)?;
    // SAFETY: `w` is NUL-terminated.
    if unsafe { SetCurrentDirectoryW(w.as_ptr()) } == 0 {
        return Err(Fail::errno(sys::errno(), "chdir", path));
    }
    Ok(())
}

/// `hostos.SendSignal`: signal 0 probes the process, 2, 9 and 15 terminate it.
pub fn send_signal(pid: i64, signal: i64) -> Res<()> {
    if !(-2_147_483_648..=2_147_483_647).contains(&pid) || !(0..=64).contains(&signal) {
        return Err(Fail::invalid());
    }
    if pid <= 0 {
        return Err(Fail::raw(sys::EINVAL));
    }
    // SAFETY: plain query.
    let process = unsafe {
        OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE,
            0,
            pid as u32,
        )
    };
    if process.is_null() {
        let mut m = b"OpenProcess: ".to_vec();
        m.extend_from_slice(describe(sys::errno()).as_bytes());
        return Err(Fail {
            status: ms_rt_abi::STATUS_FAILED,
            message: Some(m),
        });
    }
    let result = match signal {
        0 => {
            let mut code = 0u32;
            // SAFETY: `code` is writable.
            if unsafe { GetExitCodeProcess(process, &mut code) } == 0 {
                Err(Fail::raw(sys::errno()))
            } else if code != 259 {
                Err(Fail::status(STATUS_NOT_FOUND))
            } else {
                Ok(())
            }
        }
        2 | 9 | 15 => {
            // SAFETY: the process handle is open.
            if unsafe { TerminateProcess(process, 1) } == 0 {
                Err(Fail::raw(sys::errno()))
            } else {
                Ok(())
            }
        }
        _ => Err(Fail::status(STATUS_UNSUPPORTED)),
    };
    // SAFETY: the handle is ours.
    unsafe { CloseHandle(process) };
    result
}

pub fn groups() -> Res<Vec<i64>> {
    Err(Fail::status(STATUS_UNSUPPORTED))
}

pub fn umask(mask: i64) -> Res<i64> {
    if !(0..=0o777).contains(&mask) {
        return Err(Fail::invalid());
    }
    Err(Fail::status(STATUS_UNSUPPORTED))
}

pub fn set_identity(kind: &[u8], id: i64) -> Res<()> {
    let known = matches!(kind, b"uid" | b"gid" | b"euid" | b"egid");
    if !(0..=2_147_483_647).contains(&id) || !known {
        return Err(Fail::invalid());
    }
    Err(Fail::status(STATUS_UNSUPPORTED))
}

pub fn set_groups(groups: &[i64]) -> Res<()> {
    if groups.iter().any(|g| !(0..=2_147_483_647).contains(g)) {
        return Err(Fail::invalid());
    }
    Err(Fail::status(STATUS_UNSUPPORTED))
}

pub fn initialize_groups(username: &[u8], gid: i64) -> Res<()> {
    if !(0..=2_147_483_647).contains(&gid) || username.contains(&0) {
        return Err(Fail::invalid());
    }
    Err(Fail::status(STATUS_UNSUPPORTED))
}

/// A lock-protected cell for the process title (`no_std` has no `Mutex`).
struct Title {
    locked: AtomicBool,
    value: UnsafeCell<Option<Vec<u8>>>,
}

// SAFETY: every access to `value` holds the `locked` flag.
unsafe impl Sync for Title {}

static TITLE: Title = Title {
    locked: AtomicBool::new(false),
    value: UnsafeCell::new(None),
};

impl Title {
    fn with<T>(&self, f: impl FnOnce(&mut Option<Vec<u8>>) -> T) -> T {
        while self
            .locked
            .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
            .is_err()
        {
            core::hint::spin_loop();
        }
        // SAFETY: the flag gives exclusive access until it is released below.
        let r = f(unsafe { &mut *self.value.get() });
        self.locked.store(false, Ordering::Release);
        r
    }
}

/// The path of the running executable.
fn executable() -> Res<Vec<u8>> {
    let mut buf: Vec<u16> = alloc::vec![0; 512];
    loop {
        // SAFETY: `buf` is writable for its length.
        let n =
            unsafe { GetModuleFileNameW(null_mut(), buf.as_mut_ptr(), buf.len() as u32) } as usize;
        if n == 0 {
            return Err(Fail::raw(sys::errno()));
        }
        if n >= buf.len() {
            let len = buf.len() * 2;
            buf.resize(len, 0);
            continue;
        }
        return Ok(narrow(&buf[..n]));
    }
}

pub fn title() -> Res<Vec<u8>> {
    if let Some(value) = TITLE.with(|t| t.clone()) {
        return Ok(value);
    }
    let mut buf = alloc::vec![0u16; 32768];
    // SAFETY: `buf` is writable for its length.
    let n = unsafe { GetConsoleTitleW(buf.as_mut_ptr(), buf.len() as u32) } as usize;
    if n == 0 {
        // SAFETY: plain query.
        if unsafe { GetLastError() } != 0 {
            let exe = executable()?;
            return Ok(ms_std_fs::path::base(&exe).to_vec());
        }
        return Ok(Vec::new());
    }
    utf8(narrow(&buf[..n]))
}

pub fn set_title(title: &[u8]) -> Res<()> {
    if title.contains(&0) || title.contains(&b'\n') {
        return Err(Fail::invalid());
    }
    let w = wide(title).ok_or_else(Fail::invalid)?;
    // SAFETY: `w` is NUL-terminated.
    if unsafe { SetConsoleTitleW(w.as_ptr()) } == 0 {
        let e = sys::errno();
        if e != ERROR_INVALID_HANDLE as i32 {
            return Err(Fail::raw(e));
        }
    }
    TITLE.with(|t| *t = Some(title.to_vec()));
    Ok(())
}

/// The live environment as `(name, value)` pairs; any non-UTF-8 entry is `Unsupported`.
pub fn environment() -> Res<Vec<(Vec<u8>, Vec<u8>)>> {
    // SAFETY: plain query; the block is freed below.
    let block = unsafe { GetEnvironmentStringsW() };
    if block.is_null() {
        return Err(Fail::raw(sys::errno()));
    }
    let mut out = Vec::new();
    let mut p = block;
    // SAFETY: the block is a sequence of NUL-terminated strings ended by an empty one.
    unsafe {
        while *p != 0 {
            let mut len = 0;
            while *p.add(len) != 0 {
                len += 1;
            }
            let entry = narrow(core::slice::from_raw_parts(p, len));
            p = p.add(len + 1);
            // Entries such as `=C:=C:\dir` carry per-drive directories, not variables.
            if entry.first() == Some(&b'=') {
                continue;
            }
            if let Some(at) = entry.iter().position(|&c| c == b'=') {
                out.push((entry[..at].to_vec(), entry[at + 1..].to_vec()));
            }
        }
        FreeEnvironmentStringsW(block);
    }
    Ok(out)
}

pub fn set_environment(name: &[u8], value: Option<&[u8]>) -> Res<()> {
    if name.is_empty() || name.contains(&b'=') || name.contains(&0) {
        return Err(Fail::invalid());
    }
    let n = wide(name).ok_or_else(Fail::invalid)?;
    let v = match value {
        Some(v) => Some(wide(v).ok_or_else(Fail::invalid)?),
        None => None,
    };
    // SAFETY: both strings are NUL-terminated; a null value deletes the variable.
    let ok =
        unsafe { SetEnvironmentVariableW(n.as_ptr(), v.as_ref().map_or(null(), |v| v.as_ptr())) };
    if ok == 0 {
        let op = if value.is_some() {
            "setenv"
        } else {
            "unsetenv"
        };
        return Err(Fail::errno(sys::errno(), op, name));
    }
    Ok(())
}

fn micros(t: FILETIME) -> i64 {
    ((t.dwHighDateTime as i64) << 32 | t.dwLowDateTime as i64) / 10
}

pub fn resource_usage() -> Res<Usage> {
    // SAFETY: plain query of the pseudo handle.
    let process = unsafe { GetCurrentProcess() };
    let zero = FILETIME {
        dwLowDateTime: 0,
        dwHighDateTime: 0,
    };
    let (mut creation, mut exit, mut kernel, mut user) = (zero, zero, zero, zero);
    // SAFETY: all outputs are writable.
    if unsafe { GetProcessTimes(process, &mut creation, &mut exit, &mut kernel, &mut user) } == 0 {
        return Err(Fail::raw(sys::errno()));
    }
    let memory = memory_counters()?;
    // SAFETY: a zeroed `IO_COUNTERS` is a valid out buffer.
    let mut io: IO_COUNTERS = unsafe { core::mem::zeroed() };
    // SAFETY: `io` is writable.
    if unsafe { GetProcessIoCounters(process, &mut io) } == 0 {
        return Err(Fail::raw(sys::errno()));
    }
    Ok(Usage {
        user_us: micros(user),
        system_us: micros(kernel),
        max_rss: memory.PeakWorkingSetSize as i64,
        minor_faults: 0,
        major_faults: 0,
        reads: io.ReadOperationCount as i64,
        writes: io.WriteOperationCount as i64,
        voluntary: 0,
        involuntary: 0,
    })
}

fn memory_counters() -> Res<PROCESS_MEMORY_COUNTERS> {
    // SAFETY: a zeroed counters struct is a valid out buffer once `cb` is set.
    let mut counters: PROCESS_MEMORY_COUNTERS = unsafe { core::mem::zeroed() };
    counters.cb = core::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
    // SAFETY: `counters` is writable for `cb` bytes.
    if unsafe { K32GetProcessMemoryInfo(GetCurrentProcess(), &mut counters, counters.cb) } == 0 {
        return Err(Fail::raw(sys::errno()));
    }
    Ok(counters)
}

/// The parent process id, found by walking a process snapshot.
fn parent_pid(pid: u32) -> i64 {
    // SAFETY: plain snapshot.
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot as isize == -1 {
        return 0;
    }
    // SAFETY: a zeroed entry is valid once `dwSize` is set.
    let mut entry: PROCESSENTRY32W = unsafe { core::mem::zeroed() };
    entry.dwSize = core::mem::size_of::<PROCESSENTRY32W>() as u32;
    let mut parent = 0;
    // SAFETY: `snapshot` is open and `entry` writable.
    let mut more = unsafe { Process32FirstW(snapshot, &mut entry) } != 0;
    while more {
        if entry.th32ProcessID == pid {
            parent = entry.th32ParentProcessID as i64;
            break;
        }
        // SAFETY: as above.
        more = unsafe { Process32NextW(snapshot, &mut entry) } != 0;
    }
    // SAFETY: the snapshot handle is ours.
    unsafe { CloseHandle(snapshot as HANDLE) };
    parent
}

pub fn info() -> Res<Info> {
    let executable = utf8(executable()?)?;
    // SAFETY: plain query.
    let pid = unsafe { GetCurrentProcessId() };
    // Windows has no user or group ids; Go reports -1 for each.
    Ok(Info {
        pid: pid as i64,
        parent_pid: parent_pid(pid),
        executable,
        uid: -1,
        gid: -1,
        effective_uid: -1,
        effective_gid: -1,
    })
}

/// There is no cgroup-style limit on Windows.
pub fn memory_limit() -> Res<(i64, i64)> {
    Ok((0, 0))
}

/// Physical memory the host reports as available.
pub fn host_available_memory() -> Res<i64> {
    // SAFETY: a zeroed struct is valid once `dwLength` is set.
    let mut status: MEMORYSTATUSEX = unsafe { core::mem::zeroed() };
    status.dwLength = core::mem::size_of::<MEMORYSTATUSEX>() as u32;
    // SAFETY: `status` is writable.
    if unsafe { GlobalMemoryStatusEx(&mut status) } == 0 {
        return Err(Fail::raw(sys::errno()));
    }
    Ok(status.ullAvailPhys.min(i64::MAX as u64) as i64)
}

/// Resident set size in bytes (the working set).
pub fn resident_bytes() -> Res<i64> {
    Ok(memory_counters()?.WorkingSetSize as i64)
}
