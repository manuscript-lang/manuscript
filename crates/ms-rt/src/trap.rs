//! Catching a programming fault: `expect_fault` runs the operation in a forked child.
//!
//! The runtime has no unwinding, so a fault ends the process. `msrt_trap_begin` forks; the
//! child's stderr is a pipe, runs the operation, and calls `msrt_trap_end` (exit 0) when it
//! returns. The parent calls `msrt_trap_wait`, which reports whether the child faulted and
//! with which message (the first line of the fault report).

use crate::global::Global;
use crate::string;
use crate::sys;
use ms_rt_abi::StrVal;

/// Read end of the child's stderr pipe and the child's process id.
static TRAP: Global<(i32, i32)> = Global::new((-1, 0));

/// Forks. Returns 0 in the child (run the operation, then `msrt_trap_end`) and 1 in the
/// parent (call `msrt_trap_wait`).
#[unsafe(no_mangle)]
pub extern "C" fn msrt_trap_begin() -> u8 {
    crate::io::flush_stdout();
    let mut fds = [0i32; 2];
    // SAFETY: `fds` holds the two descriptors `pipe` writes.
    unsafe {
        if sys::pipe(fds.as_mut_ptr()) != 0 {
            crate::fault!("expect_fault: cannot create a pipe");
        }
        let pid = sys::fork();
        if pid < 0 {
            crate::fault!("expect_fault: cannot fork");
        }
        if pid == 0 {
            sys::close(fds[0]);
            sys::dup2(fds[1], sys::STDERR);
            sys::close(fds[1]);
            return 0;
        }
        sys::close(fds[1]);
        *TRAP.ptr() = (fds[0], pid);
    }
    1
}

/// Ends the child after the operation returned without a fault.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_trap_end() -> ! {
    crate::io::flush_stdout();
    // SAFETY: terminating the child process.
    unsafe { sys::_exit(0) }
}

/// Waits for the child. Returns 1 when the operation faulted (the message is written to `out`),
/// 0 when it ended another way.
///
/// # Safety
/// `out` must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_trap_wait(out: *mut StrVal) -> u8 {
    // SAFETY: single threaded access to the trap state; `out` is writable.
    unsafe {
        let (fd, pid) = *TRAP.ptr();
        let mut report = Vec::new();
        let mut chunk = [0u8; 4096];
        loop {
            let n = sys::read(fd, chunk.as_mut_ptr().cast(), chunk.len());
            if n <= 0 {
                break;
            }
            report.extend_from_slice(&chunk[..n as usize]);
        }
        sys::close(fd);
        let mut status = 0;
        sys::waitpid(pid, &mut status, 0);
        let exited = status & 0x7f == 0;
        let code = (status >> 8) & 0xff;
        if !(exited && code == ms_rt_abi::EXIT_FAULT) {
            return 0;
        }
        let text = report.as_slice();
        let line = text.split(|b| *b == b'\n').next().unwrap_or(text);
        *out = string::from_bytes(line);
        1
    }
}
