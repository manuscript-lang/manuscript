//! Unix child processes: `posix_spawnp` in a new process group so a kill reaches the whole tree.
use super::{Fd, STATUS_FAILED, STATUS_UNAVAILABLE};
use alloc::vec::Vec;
use core::ptr;
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys;

pub fn now_ns() -> i64 {
    // SAFETY: zeroed `timespec` is a valid out buffer.
    let mut t: libc::timespec = unsafe { core::mem::zeroed() };
    // SAFETY: `t` is writable.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut t) };
    t.tv_sec as i64 * 1_000_000_000 + t.tv_nsec as i64
}

pub fn pipe() -> Result<(Fd, Fd), i32> {
    let mut fds = [0i32; 2];
    // SAFETY: `fds` has room for two descriptors.
    if unsafe { sys::pipe_cloexec(&mut fds, false) } != 0 {
        return Err(sys::errno());
    }
    Ok((Fd(fds[0]), Fd(fds[1])))
}

pub fn set_nonblocking(fd: sys::Fd, _write_end: bool) {
    // SAFETY: plain fcntl calls.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
    }
}

/// A started child: its process id and, once reaped, its exit code.
pub struct Child {
    pub pid: libc::pid_t,
    pub code: Option<i64>,
}

fn exit_code(status: i32) -> i64 {
    if libc::WIFEXITED(status) {
        libc::WEXITSTATUS(status) as i64
    } else {
        -1
    }
}

impl Child {
    /// Reaps the child when it has exited; reports whether it has.
    pub fn poll(&mut self) -> bool {
        if self.code.is_some() {
            return true;
        }
        let mut status = 0;
        loop {
            // SAFETY: `status` is writable.
            let r = unsafe { libc::waitpid(self.pid, &mut status, libc::WNOHANG) };
            if r == self.pid {
                self.code = Some(exit_code(status));
                return true;
            }
            if r < 0 && sys::errno() == libc::EINTR {
                continue;
            }
            // 0: still running; an error such as ECHILD leaves nothing to wait for.
            if r < 0 {
                self.code = Some(-1);
                return true;
            }
            return false;
        }
    }

    pub fn wait(&mut self) -> i64 {
        while self.code.is_none() {
            let mut status = 0;
            // SAFETY: `status` is writable.
            let r = unsafe { libc::waitpid(self.pid, &mut status, 0) };
            if r == self.pid {
                self.code = Some(exit_code(status));
            } else if r < 0 && sys::errno() != libc::EINTR {
                self.code = Some(-1);
            }
        }
        self.code.unwrap_or(-1)
    }

    /// Whether the child has exited, without reaping it.
    fn exited(&self) -> bool {
        if self.code.is_some() {
            return true;
        }
        // SAFETY: zeroed `siginfo_t` is a valid out buffer.
        let mut info: libc::siginfo_t = unsafe { core::mem::zeroed() };
        // SAFETY: `info` is writable; WNOWAIT leaves the child waitable.
        let r = unsafe {
            libc::waitid(
                libc::P_PID,
                self.pid as libc::id_t,
                &mut info,
                libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
            )
        };
        // SAFETY: a successful `waitid` fills `si_pid` (zero while the child still runs).
        r == 0 && unsafe { info.si_pid() } != 0
    }

    /// Signals the child's process group (SIGTERM unless `force`, falling back to SIGKILL).
    pub fn signal(&self, force: bool) {
        if self.exited() {
            return;
        }
        // SAFETY: plain system calls on this child's group.
        unsafe {
            if !force && libc::kill(-self.pid, libc::SIGTERM) == 0 {
                return;
            }
            libc::kill(-self.pid, libc::SIGKILL);
        }
    }

    /// Kills whatever is left of the child's process group.
    pub fn kill_group(&self) {
        // SAFETY: plain system call.
        unsafe { libc::kill(-self.pid, libc::SIGKILL) };
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
    let mut owned: Vec<Vec<u8>> = Vec::with_capacity(args.len() + 1);
    for a in core::iter::once(program).chain(args.iter().map(|a| a.as_slice())) {
        let mut c = a.to_vec();
        c.push(0);
        owned.push(c);
    }
    let mut argv: Vec<*mut libc::c_char> = owned
        .iter_mut()
        .map(|a| a.as_mut_ptr() as *mut libc::c_char)
        .collect();
    argv.push(ptr::null_mut());

    // SAFETY: zeroed attribute and action blocks are initialised by the init calls below.
    let (mut attr, mut actions): (libc::posix_spawnattr_t, libc::posix_spawn_file_actions_t) =
        unsafe { (core::mem::zeroed(), core::mem::zeroed()) };
    // SAFETY: standard spawn setup; every structure is destroyed before returning.
    unsafe {
        libc::posix_spawnattr_init(&mut attr);
        libc::posix_spawn_file_actions_init(&mut actions);
        let mut empty: libc::sigset_t = core::mem::zeroed();
        libc::sigemptyset(&mut empty);
        libc::posix_spawnattr_setsigmask(&mut attr, &empty);
        libc::posix_spawnattr_setpgroup(&mut attr, 0);
        libc::posix_spawnattr_setflags(
            &mut attr,
            (libc::POSIX_SPAWN_SETPGROUP | libc::POSIX_SPAWN_SETSIGMASK) as _,
        );
        libc::posix_spawn_file_actions_adddup2(&mut actions, stdin, 0);
        libc::posix_spawn_file_actions_adddup2(&mut actions, stdout, 1);
        libc::posix_spawn_file_actions_adddup2(&mut actions, stderr, 2);
    }
    let mut pid: libc::pid_t = 0;
    // SAFETY: `argv` is NULL-terminated C strings; `environ` is the live environment.
    let r = unsafe {
        libc::posix_spawnp(
            &mut pid,
            owned[0].as_ptr() as *const libc::c_char,
            &actions,
            &attr,
            argv.as_ptr(),
            environ,
        )
    };
    // SAFETY: both were initialised above.
    unsafe {
        libc::posix_spawn_file_actions_destroy(&mut actions);
        libc::posix_spawnattr_destroy(&mut attr);
    }
    match r {
        0 => Ok(Child { pid, code: None }),
        libc::ENOENT => Err(Fail::status(STATUS_UNAVAILABLE)),
        e => {
            let mut m = b"fork/exec ".to_vec();
            m.extend_from_slice(program);
            m.extend_from_slice(b": ");
            m.extend_from_slice(describe(e).as_bytes());
            Err(Fail {
                status: STATUS_FAILED,
                message: Some(m),
            })
        }
    }
}

unsafe extern "C" {
    static environ: *const *mut libc::c_char;
}

/// Waits up to `slice_ms` for the parent ends of the pipes: which of `[stdin writable, stdout
/// readable, stderr readable]` are ready. A negative descriptor is skipped.
pub fn wait_io(fds: [sys::Fd; 3], slice_ms: i64) -> [bool; 3] {
    let mut polls = [libc::pollfd {
        fd: -1,
        events: 0,
        revents: 0,
    }; 3];
    for (i, events) in [libc::POLLOUT, libc::POLLIN, libc::POLLIN]
        .into_iter()
        .enumerate()
    {
        if fds[i] >= 0 {
            polls[i] = libc::pollfd {
                fd: fds[i],
                events,
                revents: 0,
            };
        }
    }
    // Pipes closed and the child still running: sleep a short slice instead of polling nothing.
    let slice = if fds.iter().all(|&p| p < 0) {
        slice_ms.min(2)
    } else {
        slice_ms
    };
    // SAFETY: `polls` is valid for three entries.
    unsafe { libc::poll(polls.as_mut_ptr(), 3, slice as i32) };
    [
        polls[0].revents != 0,
        polls[1].revents != 0,
        polls[2].revents != 0,
    ]
}

/// Sleeps `ms` milliseconds.
pub fn sleep_ms(ms: i64) {
    sys::sleep_ms(ms as i32);
}

/// Whether a read or write would only have blocked (`EAGAIN`).
pub fn would_block(e: i32) -> bool {
    e == libc::EAGAIN
}
