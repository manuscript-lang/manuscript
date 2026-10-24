//! Starting and reaping children with `std::process::Command`, on every platform.
//!
//! The child gets the given pipe ends as its standard streams (std duplicates them) and leads its
//! own process group on Unix; on Windows it is put in a job object right after it starts, so a
//! kill reaches its whole process tree.
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
    /// A pidfd that becomes readable when the child exits, or -1 before Linux 5.3.
    #[cfg(target_os = "linux")]
    pidfd: i32,
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

/// A duplicate of the pipe end, owned by the `Stdio` it is passed as.
fn stdio(fd: sys::Fd) -> Result<Stdio, i32> {
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

/// Starts `program` with `args` and the given standard descriptors; `Unavailable` when it is missing.
pub fn start(
    program: &[u8],
    args: &[Vec<u8>],
    stdin: sys::Fd,
    stdout: sys::Fd,
    stderr: sys::Fd,
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
    cmd.stdin(stdio(stdin).map_err(failed)?);
    cmd.stdout(stdio(stdout).map_err(failed)?);
    cmd.stderr(stdio(stderr).map_err(failed)?);
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        use windows_sys::Win32::System::Threading::{CREATE_NEW_PROCESS_GROUP, CREATE_NO_WINDOW};
        cmd.creation_flags(CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW);
    }
    match cmd.spawn() {
        Ok(inner) => Ok(Child::new(inner)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Err(Fail::status(STATUS_UNAVAILABLE)),
        Err(e) => Err(failed(e.raw_os_error().unwrap_or(0))),
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
            Child {
                inner,
                code: None,
                job: job as isize,
            }
        }
        #[cfg(target_os = "linux")]
        {
            // SAFETY: plain system call; the child is unreaped, so its pid is still its own.
            let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, inner.id() as libc::pid_t, 0) };
            Child {
                inner,
                code: None,
                pidfd: fd as i32,
            }
        }
        #[cfg(not(any(windows, target_os = "linux")))]
        Child { inner, code: None }
    }

    /// A descriptor that becomes readable when the child exits, when the platform has one.
    pub fn exit_fd(&self) -> Option<sys::Fd> {
        #[cfg(target_os = "linux")]
        if self.pidfd >= 0 {
            return Some(self.pidfd);
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

#[cfg(target_os = "linux")]
impl Drop for Child {
    fn drop(&mut self) {
        if self.pidfd >= 0 {
            let _ = sys::close(self.pidfd);
        }
    }
}
