//! Process information on Windows: there are no user or group ids; Go reports -1 for each.
use crate::control::{Info, executable};
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::sys;
use windows_sys::Win32::Foundation::{CloseHandle, HANDLE};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS};
use windows_sys::Win32::System::Threading::{GetCurrentProcess, GetCurrentProcessId};

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
    let executable = executable()?;
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

/// Resident set size in bytes (the working set).
pub fn resident_bytes() -> Res<i64> {
    Ok(memory_counters()?.WorkingSetSize as i64)
}
