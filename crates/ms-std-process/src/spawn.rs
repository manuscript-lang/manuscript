//! Starting and reaping children with `std::process::Command`, on every platform.
//!
//! Each standard stream of the child is a given pipe end (std duplicates it), the parent's own
//! stream, or the null device. The child leads its own process group on Unix; on Windows it starts
//! suspended and runs only once it is in a job object, so a kill reaches its whole process tree,
//! including anything it starts right away.
use crate::ipc::ChildEnd;
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_FAILED, STATUS_UNAVAILABLE};
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys;
use std::ffi::OsString;
use std::process::{Command, Stdio};

/// A started child: the std handle and, once reaped, its exit code (`-1` when it was killed by a
/// signal).
pub struct Child {
    inner: std::process::Child,
    pub code: Option<i64>,
    #[cfg(windows)]
    job: isize,
    /// A descriptor that becomes readable when the child exits, or -1: a pidfd on Linux (none
    /// before 5.3), a kqueue watching the pid on Apple platforms.
    #[cfg(unix)]
    exit: i32,
}

#[cfg(unix)]
fn os_string(bytes: &[u8]) -> OsString {
    use std::os::unix::ffi::OsStringExt;
    OsString::from_vec(bytes.to_vec())
}

#[cfg(windows)]
fn os_string(bytes: &[u8]) -> OsString {
    OsString::from(alloc::string::String::from_utf8_lossy(bytes).into_owned())
}

/// Where a standard stream of the child goes.
#[derive(Clone, Copy)]
pub enum StdStream {
    /// This pipe end, duplicated for the child.
    Pipe(sys::Fd),
    /// The parent's own stream.
    Inherit,
    /// The null device.
    Null,
}

impl StdStream {
    fn stdio(self) -> Result<Stdio, i32> {
        match self {
            StdStream::Pipe(fd) => duplicate(fd),
            StdStream::Inherit => Ok(Stdio::inherit()),
            StdStream::Null => Ok(Stdio::null()),
        }
    }
}

/// A duplicate of the pipe end, owned by the `Stdio` it is passed as.
fn duplicate(fd: sys::Fd) -> Result<Stdio, i32> {
    #[cfg(unix)]
    {
        use std::os::fd::BorrowedFd;
        // SAFETY: `fd` is an open pipe end for the duration of this call.
        let borrowed = unsafe { BorrowedFd::borrow_raw(fd) };
        borrowed
            .try_clone_to_owned()
            .map(Stdio::from)
            .map_err(|e| e.raw_os_error().unwrap_or(0))
    }
    #[cfg(windows)]
    {
        use std::os::windows::io::{BorrowedHandle, RawHandle};
        // SAFETY: `fd` is an open pipe handle for the duration of this call.
        let borrowed = unsafe { BorrowedHandle::borrow_raw(fd as RawHandle) };
        borrowed
            .try_clone_to_owned()
            .map(Stdio::from)
            .map_err(|e| e.raw_os_error().unwrap_or(0))
    }
}

/// Held while a child starts, so an IPC end made inheritable reaches only its own child.
#[cfg(windows)]
static INHERIT: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Starts `program` with `args` and the given standard streams, and with the child's end of `ipc`
/// as described in `crate::ipc`; `Unavailable` when it is missing.
pub fn start(
    program: &[u8],
    args: &[Vec<u8>],
    [stdin, stdout, stderr]: [StdStream; 3],
    ipc: Option<&ChildEnd>,
) -> Res<Child> {
    let failed = |e: i32| {
        let mut m = b"fork/exec ".to_vec();
        m.extend_from_slice(program);
        m.extend_from_slice(b": ");
        m.extend_from_slice(describe(e).as_bytes());
        Fail {
            status: STATUS_FAILED,
            message: Some(m),
        }
    };
    let mut cmd = Command::new(os_string(program));
    cmd.args(args.iter().map(|a| os_string(a)));
    cmd.stdin(stdin.stdio().map_err(failed)?);
    cmd.stdout(stdout.stdio().map_err(failed)?);
    cmd.stderr(stderr.stdio().map_err(failed)?);
    if let Some(end) = ipc {
        cmd.env(crate::ipc::ENV, os_string(&end.env_value()));
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            let fd = end.end.0;
            // SAFETY: only async-signal-safe calls between fork and exec.
            unsafe {
                cmd.pre_exec(move || {
                    let target = crate::ipc::CHILD_FD;
                    // `dup2` clears close-on-exec on the copy; a descriptor already in place
                    // keeps its flag, so clear it.
                    let r = if fd == target {
                        libc::fcntl(fd, libc::F_SETFD, 0)
                    } else {
                        libc::dup2(fd, target)
                    };
                    if r < 0 {
                        return Err(std::io::Error::last_os_error());
                    }
                    Ok(())
                });
            }
        }
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        use windows_sys::Win32::System::Threading::{
            CREATE_NEW_PROCESS_GROUP, CREATE_NO_WINDOW, CREATE_SUSPENDED,
        };
        // Suspended until `Child::new` has put it in its job.
        cmd.creation_flags(CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW | CREATE_SUSPENDED);
    }
    // The child's IPC end is inheritable only while this child starts, and every start holds
    // the lock, so no other child started here inherits it.
    #[cfg(windows)]
    let _held = INHERIT.lock().unwrap_or_else(|e| e.into_inner());
    #[cfg(windows)]
    if let Some(end) = ipc {
        end.end.inherit(true).map_err(failed)?;
    }
    let spawned = cmd.spawn();
    #[cfg(windows)]
    if let Some(end) = ipc {
        let _ = end.end.inherit(false);
    }
    match spawned {
        Ok(inner) => Ok(Child::new(inner)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Err(Fail::status(STATUS_UNAVAILABLE)),
        Err(e) => Err(failed(e.raw_os_error().unwrap_or(0))),
    }
}

/// Resumes the threads of the suspended process `pid`: just its main thread, since it has run
/// no code yet.
#[cfg(windows)]
fn resume(pid: u32) {
    use windows_sys::Win32::Foundation::{CloseHandle, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, TH32CS_SNAPTHREAD, THREADENTRY32, Thread32First, Thread32Next,
    };
    use windows_sys::Win32::System::Threading::{OpenThread, ResumeThread, THREAD_SUSPEND_RESUME};
    // SAFETY: a thread snapshot walked with a correctly sized entry; each opened thread handle is
    // closed once.
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        if snap == INVALID_HANDLE_VALUE {
            return;
        }
        let mut entry: THREADENTRY32 = core::mem::zeroed();
        entry.dwSize = core::mem::size_of::<THREADENTRY32>() as u32;
        let mut more = Thread32First(snap, &mut entry) != 0;
        while more {
            if entry.th32OwnerProcessID == pid {
                let thread = OpenThread(THREAD_SUSPEND_RESUME, 0, entry.th32ThreadID);
                if !thread.is_null() {
                    ResumeThread(thread);
                    CloseHandle(thread);
                }
            }
            more = Thread32Next(snap, &mut entry) != 0;
        }
        CloseHandle(snap);
    }
}

/// A pidfd for the unreaped child `pid`, or -1 before Linux 5.3.
#[cfg(target_os = "linux")]
fn exit_descriptor(pid: libc::pid_t) -> i32 {
    // SAFETY: plain system call; the child is unreaped, so its pid is still its own.
    unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0) as i32 }
}

/// A kqueue with one `EVFILT_PROC`/`NOTE_EXIT` event for the unreaped child `pid`. The event is
/// never retrieved, so once the child exits the kqueue stays readable, as a pidfd does.
#[cfg(all(unix, not(target_os = "linux")))]
fn exit_descriptor(pid: libc::pid_t) -> i32 {
    // SAFETY: plain system calls; `change` outlives the `kevent` call.
    unsafe {
        let kq = libc::kqueue();
        if kq < 0 {
            return -1;
        }
        libc::fcntl(kq, libc::F_SETFD, libc::FD_CLOEXEC);
        let mut change: libc::kevent = core::mem::zeroed();
        change.ident = pid as libc::uintptr_t;
        change.filter = libc::EVFILT_PROC;
        change.flags = libc::EV_ADD;
        change.fflags = libc::NOTE_EXIT;
        // A child that already exited cannot be watched (`ESRCH`); the caller's next reap sees it.
        if libc::kevent(kq, &change, 1, core::ptr::null_mut(), 0, core::ptr::null()) < 0 {
            libc::close(kq);
            return -1;
        }
        kq
    }
}

fn exit_code(status: std::process::ExitStatus) -> i64 {
    #[cfg(windows)]
    {
        status.code().map_or(-1, |c| c as u32 as i64)
    }
    #[cfg(not(windows))]
    {
        status.code().map_or(-1, i64::from)
    }
}

impl Child {
    fn new(inner: std::process::Child) -> Child {
        #[cfg(windows)]
        {
            use std::os::windows::io::AsRawHandle;
            use windows_sys::Win32::System::JobObjects::{
                AssignProcessToJobObject, CreateJobObjectW,
            };
            // SAFETY: plain job creation; a failed assignment (the process may already be in a
            // job without nesting support) leaves only the process itself killable.
            let job = unsafe { CreateJobObjectW(core::ptr::null(), core::ptr::null()) };
            if !job.is_null() {
                // SAFETY: both handles are open.
                unsafe { AssignProcessToJobObject(job, inner.as_raw_handle() as _) };
            }
            resume(inner.id());
            Child {
                inner,
                code: None,
                job: job as isize,
            }
        }
        #[cfg(unix)]
        {
            let exit = exit_descriptor(inner.id() as libc::pid_t);
            Child {
                inner,
                code: None,
                exit,
            }
        }
    }

    /// A descriptor that becomes readable when the child exits, when the platform has one.
    pub fn exit_fd(&self) -> Option<sys::Fd> {
        #[cfg(unix)]
        if self.exit >= 0 {
            return Some(self.exit);
        }
        None
    }

    /// Parks the task until the child exits or `timeout_ns` passes (negative: no limit). False
    /// when the platform cannot wait on the child, so the caller checks it in slices instead.
    pub fn park_until_exit(&mut self, timeout_ns: i64) -> bool {
        #[cfg(unix)]
        if let Some(fd) = self.exit_fd() {
            ms_rt::glue::task_wait_fd(fd, ms_rt::glue::WAIT_READ, timeout_ns);
            return true;
        }
        let _ = timeout_ns;
        false
    }

    /// Reaps the child when it has exited; reports whether it has.
    pub fn poll(&mut self) -> bool {
        if self.code.is_some() {
            return true;
        }
        match self.inner.try_wait() {
            Ok(Some(status)) => self.code = Some(exit_code(status)),
            Ok(None) => return false,
            // Nothing left to wait for.
            Err(_) => self.code = Some(-1),
        }
        true
    }

    pub fn wait(&mut self) -> i64 {
        if self.code.is_none() {
            self.code = Some(self.inner.wait().map_or(-1, exit_code));
        }
        self.code.unwrap_or(-1)
    }

    /// Signals the child's process group (SIGTERM unless `force`, falling back to SIGKILL).
    /// Windows has no graceful signal: the whole job is terminated.
    pub fn signal(&mut self, force: bool) {
        if self.poll() {
            return;
        }
        #[cfg(unix)]
        {
            let pid = self.inner.id() as libc::pid_t;
            // SAFETY: plain system calls on this child's group.
            unsafe {
                if !force && libc::kill(-pid, libc::SIGTERM) == 0 {
                    return;
                }
                libc::kill(-pid, libc::SIGKILL);
            }
        }
        #[cfg(windows)]
        {
            let _ = force;
            self.kill_group();
        }
    }

    /// Kills whatever is left of the child's process group (job on Windows).
    pub fn kill_group(&mut self) {
        #[cfg(unix)]
        {
            let pid = self.inner.id() as libc::pid_t;
            // SAFETY: plain system call.
            unsafe { libc::kill(-pid, libc::SIGKILL) };
        }
        #[cfg(windows)]
        {
            use windows_sys::Win32::System::JobObjects::TerminateJobObject;
            // SAFETY: the job handle is open until `drop`.
            unsafe { TerminateJobObject(self.job as _, 1) };
            let _ = self.inner.kill();
        }
    }
}

#[cfg(windows)]
impl Drop for Child {
    fn drop(&mut self) {
        // SAFETY: the job handle is ours and closed once.
        unsafe { windows_sys::Win32::Foundation::CloseHandle(self.job as _) };
    }
}

#[cfg(unix)]
impl Drop for Child {
    fn drop(&mut self) {
        if self.exit >= 0 {
            let _ = sys::close(self.exit);
        }
    }
}
