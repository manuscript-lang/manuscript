//! Windows child processes: `CreateProcessW` with explicit standard handles, the child held in a
//! job object so killing the job reaches its whole process tree (the counterpart of the Unix
//! process group). As in Go, there is no graceful signal: stopping a child terminates it with
//! exit code 1.
use super::{Fd, STATUS_FAILED, STATUS_UNAVAILABLE};
use alloc::vec::Vec;
use core::ptr::{null, null_mut};
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys;
use windows_sys::Win32::Foundation::{
    CloseHandle, HANDLE, HANDLE_FLAG_INHERIT, SetHandleInformation, WAIT_OBJECT_0,
};
use windows_sys::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, TerminateJobObject,
};
use windows_sys::Win32::System::Performance::{QueryPerformanceCounter, QueryPerformanceFrequency};
use windows_sys::Win32::System::Pipes::{CreatePipe, PIPE_NOWAIT, SetNamedPipeHandleState};
use windows_sys::Win32::System::Threading::{
    CREATE_NEW_PROCESS_GROUP, CREATE_NO_WINDOW, CREATE_SUSPENDED, CreateProcessW,
    DeleteProcThreadAttributeList, EXTENDED_STARTUPINFO_PRESENT, GetExitCodeProcess, INFINITE,
    InitializeProcThreadAttributeList, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, PROCESS_INFORMATION,
    ResumeThread, STARTF_USESTDHANDLES, STARTUPINFOEXW, TerminateProcess,
    UpdateProcThreadAttribute, WaitForSingleObject,
};

const STILL_ACTIVE: u32 = 259;

/// Monotonic nanoseconds (`QueryPerformanceCounter`).
pub fn now_ns() -> i64 {
    let (mut freq, mut count) = (0i64, 0i64);
    // SAFETY: both outputs are writable.
    unsafe {
        QueryPerformanceFrequency(&mut freq);
        QueryPerformanceCounter(&mut count);
    }
    let freq = freq.max(1);
    // Split to avoid overflowing `count * 1e9`.
    (count / freq) * 1_000_000_000 + (count % freq) * 1_000_000_000 / freq
}

/// An anonymous pipe `(read, write)`. Neither end is inheritable; `start` makes the ends the child
/// uses inheritable only for the duration of the spawn.
pub fn pipe() -> Result<(Fd, Fd), i32> {
    let (mut r, mut w): (HANDLE, HANDLE) = (null_mut(), null_mut());
    // SAFETY: both outputs are writable.
    if unsafe { CreatePipe(&mut r, &mut w, null(), 0) } == 0 {
        return Err(sys::errno());
    }
    Ok((Fd(r as isize), Fd(w as isize)))
}

/// Puts the parent's write end into non-blocking mode so a full pipe does not stall the loop.
/// Read ends are polled with `PeekNamedPipe` instead.
pub fn set_nonblocking(fd: sys::Fd, write_end: bool) {
    if write_end {
        let mode = PIPE_NOWAIT;
        // SAFETY: `fd` is an open pipe handle and `mode` is readable.
        unsafe { SetNamedPipeHandleState(fd as HANDLE, &mode, null(), null()) };
    }
}

/// A started child: its process handle, job object and, once it exited, its exit code.
pub struct Child {
    process: isize,
    job: isize,
    pub code: Option<i64>,
}

impl Child {
    fn exit_status(&mut self) -> bool {
        // SAFETY: the process handle is open.
        if unsafe { WaitForSingleObject(self.process as HANDLE, 0) } != WAIT_OBJECT_0 {
            return false;
        }
        let mut code = STILL_ACTIVE;
        // SAFETY: `code` is writable.
        if unsafe { GetExitCodeProcess(self.process as HANDLE, &mut code) } == 0 {
            self.code = Some(-1);
        } else {
            self.code = Some(code as i64);
        }
        true
    }

    /// Records the exit code when the child has exited; reports whether it has.
    pub fn poll(&mut self) -> bool {
        self.code.is_some() || self.exit_status()
    }

    pub fn wait(&mut self) -> i64 {
        if self.code.is_none() {
            // SAFETY: the process handle is open.
            unsafe { WaitForSingleObject(self.process as HANDLE, INFINITE) };
            self.exit_status();
        }
        self.code.unwrap_or(-1)
    }

    /// Terminates the child's job (Windows has no graceful signal; `force` is ignored).
    pub fn signal(&self, _force: bool) {
        self.kill_group();
    }

    /// Terminates every process in the child's job.
    pub fn kill_group(&self) {
        // SAFETY: the job and process handles are open.
        unsafe {
            TerminateJobObject(self.job as HANDLE, 1);
            TerminateProcess(self.process as HANDLE, 1);
        }
    }
}

impl Drop for Child {
    fn drop(&mut self) {
        // SAFETY: both handles are ours and closed once.
        unsafe {
            CloseHandle(self.process as HANDLE);
            CloseHandle(self.job as HANDLE);
        }
    }
}

/// `syscall.EscapeArg`: quotes one argument for a Windows command line.
fn escape_arg(s: &[u8], out: &mut Vec<u8>) {
    if s.is_empty() {
        out.extend_from_slice(b"\"\"");
        return;
    }
    let needs_backslash = s.iter().any(|&c| c == b'"' || c == b'\\');
    let has_space = s.iter().any(|&c| c == b' ' || c == b'\t');
    if !needs_backslash && !has_space {
        out.extend_from_slice(s);
        return;
    }
    if !needs_backslash {
        out.push(b'"');
        out.extend_from_slice(s);
        out.push(b'"');
        return;
    }
    if has_space {
        out.push(b'"');
    }
    let mut slashes = 0;
    for &c in s {
        match c {
            b'\\' => slashes += 1,
            b'"' => {
                out.extend(core::iter::repeat_n(b'\\', slashes + 1));
                slashes = 0;
            }
            _ => slashes = 0,
        }
        out.push(c);
    }
    if has_space {
        out.extend(core::iter::repeat_n(b'\\', slashes));
        out.push(b'"');
    }
}

fn is_file(path: &[u8]) -> bool {
    sys::CPath::new(path)
        .and_then(|c| sys::stat(&c, true).ok())
        .is_some_and(|st| !st.is_dir())
}

/// `exec.LookPath` on Windows: a name with a separator or drive is used as is, otherwise each
/// `PATH` directory is searched, trying the `PATHEXT` extensions.
fn look_path(program: &[u8]) -> Option<Vec<u8>> {
    let exts: Vec<Vec<u8>> = sys::env(c"PATHEXT")
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| b".com;.exe;.bat;.cmd".to_vec())
        .split(|&c| c == b';')
        .filter(|e| !e.is_empty())
        .map(|e| e.to_ascii_lowercase())
        .collect();
    let find = |file: &[u8]| -> Option<Vec<u8>> {
        let has_ext = file
            .iter()
            .rposition(|&c| c == b'.')
            .is_some_and(|i| i > 0 && !file[i..].iter().any(|&c| ms_std_fs::path::is_sep(c)));
        if has_ext && is_file(file) {
            return Some(file.to_vec());
        }
        exts.iter().find_map(|e| {
            let mut f = file.to_vec();
            f.extend_from_slice(e);
            is_file(&f).then_some(f)
        })
    };
    let has_sep = program
        .iter()
        .any(|&c| ms_std_fs::path::is_sep(c) || c == b':');
    if has_sep {
        return find(program);
    }
    let path = sys::env(c"PATH")?;
    path.split(|&c| c == b';')
        .filter(|d| !d.is_empty())
        .find_map(|dir| find(&ms_std_fs::path::join(dir, program)))
}

fn wide(bytes: &[u8]) -> Vec<u16> {
    let mut w: Vec<u16> = alloc::string::String::from_utf8_lossy(bytes)
        .encode_utf16()
        .collect();
    w.push(0);
    w
}

/// Starts `program` with `args` and the given standard handles; `Unavailable` when it is missing.
pub fn start(
    program: &[u8],
    args: &[Vec<u8>],
    stdin: sys::Fd,
    stdout: sys::Fd,
    stderr: sys::Fd,
) -> Res<Child> {
    let Some(resolved) = look_path(program) else {
        return Err(Fail::status(STATUS_UNAVAILABLE));
    };
    let mut cmdline: Vec<u8> = Vec::new();
    escape_arg(program, &mut cmdline);
    for a in args {
        cmdline.push(b' ');
        escape_arg(a, &mut cmdline);
    }
    let mut cmd_wide = wide(&cmdline);
    let app = wide(&resolved);

    let handles = [stdin as HANDLE, stdout as HANDLE, stderr as HANDLE];
    for h in handles {
        // SAFETY: the handles are open pipe ends.
        unsafe { SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT) };
    }
    let result = spawn(&app, &mut cmd_wide, &handles);
    for h in handles {
        // SAFETY: as above; the parent copies stop being inheritable again.
        unsafe { SetHandleInformation(h, HANDLE_FLAG_INHERIT, 0) };
    }
    match result {
        Ok(child) => Ok(child),
        Err(e) => {
            let mut m = b"fork/exec ".to_vec();
            m.extend_from_slice(&resolved);
            m.extend_from_slice(b": ");
            m.extend_from_slice(describe(e).as_bytes());
            Err(Fail {
                status: STATUS_FAILED,
                message: Some(m),
            })
        }
    }
}

fn spawn(app: &[u16], cmd: &mut [u16], handles: &[HANDLE; 3]) -> Result<Child, i32> {
    // SAFETY: a zeroed `STARTUPINFOEXW` is valid once `cb` is set.
    let mut si: STARTUPINFOEXW = unsafe { core::mem::zeroed() };
    si.StartupInfo.cb = core::mem::size_of::<STARTUPINFOEXW>() as u32;
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = handles[0];
    si.StartupInfo.hStdOutput = handles[1];
    si.StartupInfo.hStdError = handles[2];

    // Only the three pipe ends are inherited, whatever other handles happen to be inheritable.
    let mut size = 0usize;
    // SAFETY: a size query with a null list.
    unsafe { InitializeProcThreadAttributeList(null_mut(), 1, 0, &mut size) };
    let mut storage: Vec<u8> = alloc::vec![0; size];
    let list = storage.as_mut_ptr().cast();
    // SAFETY: `storage` is writable for `size` bytes.
    if unsafe { InitializeProcThreadAttributeList(list, 1, 0, &mut size) } == 0 {
        return Err(sys::errno());
    }
    // SAFETY: `handles` outlives the spawn.
    let updated = unsafe {
        UpdateProcThreadAttribute(
            list,
            0,
            PROC_THREAD_ATTRIBUTE_HANDLE_LIST as usize,
            handles.as_ptr().cast(),
            core::mem::size_of_val(handles),
            null_mut(),
            null(),
        )
    };
    if updated == 0 {
        let e = sys::errno();
        // SAFETY: the list was initialised above.
        unsafe { DeleteProcThreadAttributeList(list) };
        return Err(e);
    }
    si.lpAttributeList = list;

    // SAFETY: a zeroed `PROCESS_INFORMATION` is a valid out buffer.
    let mut pi: PROCESS_INFORMATION = unsafe { core::mem::zeroed() };
    // SAFETY: `app` and `cmd` are NUL-terminated and `si`/`pi` are valid.
    let created = unsafe {
        CreateProcessW(
            app.as_ptr(),
            cmd.as_mut_ptr(),
            null(),
            null(),
            1,
            CREATE_SUSPENDED
                | CREATE_NEW_PROCESS_GROUP
                | CREATE_NO_WINDOW
                | EXTENDED_STARTUPINFO_PRESENT,
            null(),
            null(),
            &si.StartupInfo,
            &mut pi,
        )
    };
    let e = sys::errno();
    // SAFETY: the list was initialised above.
    unsafe { DeleteProcThreadAttributeList(list) };
    if created == 0 {
        return Err(e);
    }
    // SAFETY: plain job creation.
    let job = unsafe { CreateJobObjectW(null(), null()) };
    // SAFETY: both handles are open. A failed assignment (the process may already be in a job
    // without nesting support) leaves only the process itself killable.
    unsafe {
        if !job.is_null() {
            AssignProcessToJobObject(job, pi.hProcess);
        }
        ResumeThread(pi.hThread);
        CloseHandle(pi.hThread);
    }
    Ok(Child {
        process: pi.hProcess as isize,
        job: job as isize,
        code: None,
    })
}

/// Waits up to `slice_ms` for the parent ends of the pipes: which of `[stdin writable, stdout
/// readable, stderr readable]` are ready. An invalid handle is skipped. A Windows pipe cannot be
/// waited on for writability, so an open stdin counts as ready after a short pause and the
/// non-blocking write reports how much fit.
pub fn wait_io(fds: [sys::Fd; 3], slice_ms: i64) -> [bool; 3] {
    let open = |fd: sys::Fd| fd != sys::INVALID_FD;
    // Pipes closed and the child still running: pause briefly instead of polling nothing.
    let slice_ms = if fds.iter().any(|&fd| open(fd)) {
        slice_ms
    } else {
        slice_ms.min(2)
    };
    let mut waited = 0;
    loop {
        let ready = [
            open(fds[0]) && waited > 0,
            open(fds[1]) && sys::wait_ready(fds[1], sys::Interest::Read, 0),
            open(fds[2]) && sys::wait_ready(fds[2], sys::Interest::Read, 0),
        ];
        if ready.iter().any(|&r| r) || waited >= slice_ms {
            return ready;
        }
        sys::sleep_ms(1);
        waited += 1;
    }
}

/// Sleeps `ms` milliseconds.
pub fn sleep_ms(ms: i64) {
    sys::sleep_ms(ms as i32);
}

/// Whether a failed read or write only means "try later". A full non-blocking pipe reports
/// success with zero bytes instead, so no error qualifies.
pub fn would_block(_: i32) -> bool {
    false
}
