//! Child processes, ported from `osCommands` in `pkg/runtime/process.go`.
//!
//! Children start with `posix_spawnp` in a new process group so a kill reaches the whole tree.
//! Waiting polls in short slices, which lets a pending cancellation kill the tree and unwind.
use alloc::vec::Vec;
use core::ptr;
use ms_rt_abi::{STATUS_FAILED, STATUS_OUTPUT_LIMIT, STATUS_TIMEOUT, STATUS_UNAVAILABLE};
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys;
use ms_std_rt::{cancel_pending, cancelled};

const SLICE_MS: i32 = 50;
/// How long the pipes may stay open after the child exited (`exec.Cmd.WaitDelay`).
const WAIT_DELAY_NS: i64 = 1_000_000_000;
pub const BACKGROUND_OUTPUT: &[u8] = b"the command finished but a background process kept its output open; close or redirect its output, or set a timeout";

pub fn now_ns() -> i64 {
    // SAFETY: zeroed `timespec` is a valid out buffer.
    let mut t: libc::timespec = unsafe { core::mem::zeroed() };
    // SAFETY: `t` is writable.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut t) };
    t.tv_sec as i64 * 1_000_000_000 + t.tv_nsec as i64
}

/// A descriptor closed on drop.
pub struct Fd(pub i32);

impl Fd {
    pub fn take(&mut self) -> i32 {
        core::mem::replace(&mut self.0, -1)
    }

    pub fn close(&mut self) {
        if self.0 >= 0 {
            let _ = sys::close(self.0);
            self.0 = -1;
        }
    }
}

impl Drop for Fd {
    fn drop(&mut self) {
        self.close();
    }
}

fn pipe() -> Result<(Fd, Fd), i32> {
    let mut fds = [0i32; 2];
    // SAFETY: `fds` has room for two descriptors.
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return Err(sys::errno());
    }
    Ok((Fd(fds[0]), Fd(fds[1])))
}

fn set_nonblocking(fd: i32) {
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
pub fn start(program: &[u8], args: &[Vec<u8>], stdin: i32, stdout: i32, stderr: i32) -> Res<Child> {
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

fn start_failure(e: i32) -> Fail {
    let mut m = b"pipe: ".to_vec();
    m.extend_from_slice(describe(e).as_bytes());
    Fail {
        status: STATUS_FAILED,
        message: Some(m),
    }
}

pub struct Output {
    pub code: i64,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

/// Kills the child's group and reaps it unless it was already collected.
struct Reaper(Child);

impl Drop for Reaper {
    fn drop(&mut self) {
        if self.0.code.is_none() {
            self.0.kill_group();
            self.0.wait();
        }
    }
}

/// `run`: executes the command to completion, capturing output up to `max_output` bytes in total.
pub fn run(
    program: &[u8],
    args: &[Vec<u8>],
    input: &[u8],
    max_output: i64,
    timeout_ns: Option<i64>,
) -> Res<Output> {
    let (in_r, mut in_w) = pipe().map_err(start_failure)?;
    let (mut out_r, out_w) = pipe().map_err(start_failure)?;
    let (mut err_r, err_w) = pipe().map_err(start_failure)?;
    let child = start(program, args, in_r.0, out_w.0, err_w.0)?;
    let mut child = Reaper(child);
    drop((in_r, out_w, err_w));

    let deadline = timeout_ns.map(|t| now_ns().saturating_add(t));
    set_nonblocking(in_w.0);
    set_nonblocking(out_r.0);
    set_nonblocking(err_r.0);
    let mut written = 0usize;
    if input.is_empty() {
        in_w.close();
    }
    let (mut stdout, mut stderr): (Vec<u8>, Vec<u8>) = (Vec::new(), Vec::new());
    let mut remaining = max_output;
    let (mut overflow, mut timed_out, mut kept_open) = (false, false, false);
    let mut exited_at: Option<i64> = None;
    let mut buf = alloc::vec![0u8; 64 * 1024];

    loop {
        if cancel_pending() {
            drop(child);
            cancelled();
        }
        if !child.0.poll() {
            exited_at = None;
        } else if exited_at.is_none() {
            exited_at = Some(now_ns());
        }
        if exited_at.is_some() && out_r.0 < 0 && err_r.0 < 0 {
            break;
        }
        let now = now_ns();
        if deadline.is_some_and(|d| now >= d) {
            timed_out = true;
            child.0.kill_group();
            break;
        }
        if exited_at.is_some_and(|t| now - t >= WAIT_DELAY_NS) {
            kept_open = true;
            break;
        }
        let mut slice = SLICE_MS as i64;
        if let Some(d) = deadline {
            slice = slice.min(((d - now) / 1_000_000).max(1));
        }
        let mut fds: [libc::pollfd; 3] = [libc::pollfd {
            fd: -1,
            events: 0,
            revents: 0,
        }; 3];
        if in_w.0 >= 0 {
            fds[0] = libc::pollfd {
                fd: in_w.0,
                events: libc::POLLOUT,
                revents: 0,
            };
        }
        if out_r.0 >= 0 {
            fds[1] = libc::pollfd {
                fd: out_r.0,
                events: libc::POLLIN,
                revents: 0,
            };
        }
        if err_r.0 >= 0 {
            fds[2] = libc::pollfd {
                fd: err_r.0,
                events: libc::POLLIN,
                revents: 0,
            };
        }
        // Pipes closed and the child still running: sleep a short slice instead of polling nothing.
        let slice = if fds.iter().all(|p| p.fd < 0) {
            slice.min(2)
        } else {
            slice
        };
        // SAFETY: `fds` is valid for three entries.
        unsafe { libc::poll(fds.as_mut_ptr(), 3, slice as i32) };

        if fds[0].revents != 0 && in_w.0 >= 0 {
            let end = input.len().min(written + 64 * 1024);
            match sys::write(in_w.0, &input[written..end]) {
                Ok(n) => written += n,
                Err(libc::EAGAIN) => {}
                // The child closed its input early; the remainder is dropped.
                Err(_) => written = input.len(),
            }
            if written >= input.len() {
                in_w.close();
            }
        }
        for (slot, is_err) in [(1usize, false), (2usize, true)] {
            if fds[slot].revents == 0 {
                continue;
            }
            let reader = if is_err { &mut err_r } else { &mut out_r };
            match sys::read(reader.0, &mut buf) {
                Ok(0) => reader.close(),
                Ok(n) => {
                    let accepted = n.min(remaining.max(0) as usize);
                    let sink = if is_err { &mut stderr } else { &mut stdout };
                    sink.extend_from_slice(&buf[..accepted]);
                    remaining -= accepted as i64;
                    if accepted != n {
                        overflow = true;
                    }
                }
                Err(libc::EAGAIN) => {}
                Err(_) => reader.close(),
            }
        }
        if overflow {
            child.0.kill_group();
            break;
        }
    }
    let code = child.0.wait();
    if overflow {
        return Err(Fail::status(STATUS_OUTPUT_LIMIT));
    }
    if timed_out {
        return Err(Fail::status(STATUS_TIMEOUT));
    }
    if kept_open && code == 0 {
        return Err(Fail {
            status: STATUS_FAILED,
            message: Some(BACKGROUND_OUTPUT.to_vec()),
        });
    }
    Ok(Output {
        code,
        stdout,
        stderr,
    })
}

/// A long-lived child with its three pipes (parent ends).
pub struct Subprocess {
    pub child: Child,
    pub closed: bool,
    pub stdin: Fd,
    pub stdout: Fd,
    pub stderr: Fd,
}

pub fn spawn(program: &[u8], args: &[Vec<u8>]) -> Res<Subprocess> {
    let (in_r, in_w) = pipe().map_err(start_failure)?;
    let (out_r, out_w) = pipe().map_err(start_failure)?;
    let (err_r, err_w) = pipe().map_err(start_failure)?;
    let child = start(program, args, in_r.0, out_w.0, err_w.0)?;
    Ok(Subprocess {
        child,
        closed: false,
        stdin: in_w,
        stdout: out_r,
        stderr: err_r,
    })
}

impl Subprocess {
    /// Waits for exit, or `Timeout` when `timeout_ns` elapses first (the child keeps running).
    pub fn wait(&mut self, timeout_ns: Option<i64>) -> Res<i64> {
        let deadline = timeout_ns.map(|t| now_ns().saturating_add(t));
        loop {
            ms_std_rt::poll_cancel();
            if self.child.poll() {
                return Ok(self.child.code.unwrap_or(-1));
            }
            let now = now_ns();
            if deadline.is_some_and(|d| now >= d) {
                return Err(Fail::status(STATUS_TIMEOUT));
            }
            let slice = deadline.map_or(2, |d| ((d - now) / 1_000_000).clamp(1, 2));
            // SAFETY: no descriptors; used as a sleep.
            unsafe { libc::poll(ptr::null_mut(), 0, slice as i32) };
        }
    }

    /// Kills the group, joins the leader, kills what remains of the group.
    pub fn stop(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        self.child.signal(true);
        self.child.wait();
        self.child.kill_group();
    }
}

impl Drop for Subprocess {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_rt_abi::STATUS_UNAVAILABLE;

    fn args(list: &[&str]) -> Vec<Vec<u8>> {
        list.iter().map(|s| s.as_bytes().to_vec()).collect()
    }

    #[test]
    fn captures_output_and_exit_codes() {
        let _guard = crate::environment_guard();
        let out = run(
            b"sh",
            &args(&["-c", "cat; echo err >&2; exit 3"]),
            b"hello",
            i64::MAX,
            None,
        )
        .unwrap();
        assert_eq!(
            (out.code, out.stdout.as_slice(), out.stderr.as_slice()),
            (3, b"hello".as_slice(), b"err\n".as_slice())
        );
        let killed = run(b"sh", &args(&["-c", "kill -9 $$"]), b"", i64::MAX, None).unwrap();
        assert_eq!(killed.code, -1);
        assert_eq!(
            run(b"definitely-not-a-program", &[], b"", i64::MAX, None)
                .err()
                .unwrap()
                .status,
            STATUS_UNAVAILABLE
        );
    }

    #[test]
    fn limits_and_timeouts_kill_the_group() {
        let _guard = crate::environment_guard();
        let big = run(
            b"sh",
            &args(&["-c", "yes | head -c 100000"]),
            b"",
            1000,
            None,
        );
        assert_eq!(big.err().unwrap().status, STATUS_OUTPUT_LIMIT);
        let start = now_ns();
        let slow = run(
            b"sh",
            &args(&["-c", "sleep 30 & sleep 30"]),
            b"",
            i64::MAX,
            Some(100_000_000),
        );
        assert_eq!(slow.err().unwrap().status, STATUS_TIMEOUT);
        assert!(now_ns() - start < 5_000_000_000);
        let background = run(b"sh", &args(&["-c", "sleep 5 &"]), b"", i64::MAX, None);
        assert_eq!(
            background.err().unwrap().message.as_deref(),
            Some(BACKGROUND_OUTPUT)
        );
    }

    #[test]
    fn subprocess_pipes_and_close() {
        let _guard = crate::environment_guard();
        let mut p = spawn(b"cat", &[]).unwrap();
        assert_eq!(p.wait(Some(20_000_000)).unwrap_err().status, STATUS_TIMEOUT);
        sys::write(p.stdin.0, b"ping").unwrap();
        p.stdin.close();
        assert_eq!(p.wait(Some(5_000_000_000)).unwrap(), 0);
        let mut buf = [0u8; 8];
        assert_eq!(sys::read(p.stdout.0, &mut buf).unwrap(), 4);
        p.stop();
        let mut sleeper = spawn(b"sleep", &args(&["30"])).unwrap();
        sleeper.child.signal(false);
        assert_eq!(sleeper.wait(Some(5_000_000_000)).unwrap(), -1);
    }
}
