//! Windows pipes and readiness for child processes. The parent's end of each pipe is an
//! overlapped named pipe the runtime poller adopts, so reads, writes and `run`'s wait park on
//! the poller instead of being checked in slices; the child's end is an ordinary handle.
use super::Fd;
use alloc::vec::Vec;
use core::ptr::{null, null_mut};
use ms_rt::glue::pipe as adopted;
use ms_std_fs::sys;
use windows_sys::Win32::Foundation::{
    GENERIC_READ, GENERIC_WRITE, GetLastError, INVALID_HANDLE_VALUE, LocalFree,
};
use windows_sys::Win32::Security::Authorization::{
    ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1,
};
use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, FILE_FLAG_FIRST_PIPE_INSTANCE, FILE_FLAG_OVERLAPPED, OPEN_EXISTING,
    PIPE_ACCESS_DUPLEX, PIPE_ACCESS_INBOUND, PIPE_ACCESS_OUTBOUND,
};
use windows_sys::Win32::System::Pipes::{
    CreateNamedPipeW, PIPE_READMODE_BYTE, PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE, PIPE_WAIT,
};

const BUFFER: u32 = 64 * 1024;

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(core::iter::once(0)).collect()
}

fn last_error() -> i32 {
    // SAFETY: plain query.
    unsafe { GetLastError() as i32 }
}

/// A random name suffix: `RandomState` keys come from the system generator. The name only
/// avoids collisions; the owner-only DACL and the first-instance flag keep others out.
fn random_suffix() -> u128 {
    use core::hash::BuildHasher;
    let state = std::collections::hash_map::RandomState::new();
    (u128::from(state.hash_one(1u8)) << 64) | u128::from(state.hash_one(2u8))
}

/// A connected named pipe `(server, client)` only this user can open. The server end is
/// overlapped; `server_access` is a `PIPE_ACCESS_*` direction, and the client is opened with
/// `client_access` and `client_flags`. Neither handle is inheritable.
pub fn named_pipe(
    server_access: u32,
    client_access: u32,
    client_flags: u32,
) -> Result<(Fd, Fd), i32> {
    let name = alloc::format!(
        r"\\.\pipe\ms-{}-{:032x}",
        std::process::id(),
        random_suffix()
    );
    let wname = wide(&name);
    // Owner rights only: no other user can open the pipe.
    let sddl = wide("D:P(A;;GA;;;OW)");
    let mut sd = null_mut();
    // SAFETY: `sddl` is NUL-terminated and `sd` is writable; the descriptor is freed below.
    if unsafe {
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.as_ptr(),
            SDDL_REVISION_1,
            &mut sd,
            null_mut(),
        )
    } == 0
    {
        return Err(last_error());
    }
    let attributes = SECURITY_ATTRIBUTES {
        nLength: core::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: sd,
        bInheritHandle: 0,
    };
    // SAFETY: `wname` is NUL-terminated and `attributes` outlives the call.
    let server = unsafe {
        CreateNamedPipeW(
            wname.as_ptr(),
            server_access | FILE_FLAG_FIRST_PIPE_INSTANCE | FILE_FLAG_OVERLAPPED,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            1,
            BUFFER,
            BUFFER,
            0,
            &attributes,
        )
    };
    let error = last_error();
    // SAFETY: allocated by the conversion above.
    unsafe { LocalFree(sd) };
    if server == INVALID_HANDLE_VALUE {
        return Err(error);
    }
    let server = Fd(server as isize);
    // The parent opens the client end itself, so the pipe is connected before the child runs
    // and a child that dies at once still closes it.
    // SAFETY: `wname` is NUL-terminated.
    let client = unsafe {
        CreateFileW(
            wname.as_ptr(),
            client_access,
            0,
            null(),
            OPEN_EXISTING,
            client_flags,
            null_mut(),
        )
    };
    if client == INVALID_HANDLE_VALUE {
        return Err(last_error());
    }
    Ok((server, Fd(client as isize)))
}

/// A duplex pipe with both ends overlapped, for a child's IPC link.
pub fn duplex_pipe() -> Result<(Fd, Fd), i32> {
    named_pipe(
        PIPE_ACCESS_DUPLEX,
        GENERIC_READ | GENERIC_WRITE,
        FILE_FLAG_OVERLAPPED,
    )
}

/// A pipe `(parent, child)` for one standard stream: the parent reads it when `parent_reads`,
/// else writes it. The parent's end is adopted by the runtime poller; the child's is a plain
/// handle, as programs expect of their standard streams.
pub fn pipe(parent_reads: bool) -> Result<(Fd, Fd), i32> {
    let (server, client) = if parent_reads {
        named_pipe(PIPE_ACCESS_INBOUND, GENERIC_WRITE, 0)?
    } else {
        named_pipe(PIPE_ACCESS_OUTBOUND, GENERIC_READ, 0)?
    };
    let mut server = server;
    // SAFETY: an open overlapped pipe handle, owned by the poller from here on.
    if !unsafe { adopted::adopt(server.0) } {
        return Err(last_error());
    }
    let handle = server.take();
    Ok((Fd(handle), client))
}

/// Closes `fd`, through the poller when it adopted the pipe.
pub fn close(fd: sys::Fd) -> Result<(), i32> {
    if adopted::is_adopted(fd) {
        adopted::close(fd);
        return Ok(());
    }
    sys::close(fd)
}

/// One read without waiting: `WOULD_BLOCK` while an adopted pipe has nothing yet.
pub fn read(fd: sys::Fd, buf: &mut [u8]) -> Result<usize, i32> {
    if adopted::is_adopted(fd) {
        return adopted::try_read(fd, buf).map_err(os_error);
    }
    sys::read(fd, buf)
}

/// One write without waiting: `WOULD_BLOCK` while an earlier write to an adopted pipe is in
/// flight.
pub fn write(fd: sys::Fd, data: &[u8]) -> Result<usize, i32> {
    if adopted::is_adopted(fd) {
        return adopted::try_write(fd, data).map_err(os_error);
    }
    sys::write(fd, data)
}

/// Stands for `WouldBlock`, which carries no OS error code.
const WOULD_BLOCK: i32 = -1;

fn os_error(e: std::io::Error) -> i32 {
    if e.kind() == std::io::ErrorKind::WouldBlock {
        return WOULD_BLOCK;
    }
    e.raw_os_error().unwrap_or(0)
}

/// Adopted pipes need no mode change.
pub fn set_nonblocking(_: sys::Fd, _: bool) {}

/// Which of `[stdin, stdout, stderr]` to try: every open end, since an adopted pipe only tells
/// readiness by a read or write that does not block. The caller parks when none made progress.
pub fn wait_io(fds: [sys::Fd; 3], _: i64) -> [bool; 3] {
    fds.map(|fd| fd != sys::INVALID_FD)
}

/// Whether a failed read or write only means "try later".
pub fn would_block(e: i32) -> bool {
    e == WOULD_BLOCK
}

/// Parks `run` on the child's exit and its pipes at once: the poller wakes the task waiting on
/// the process handle when the child exits or any grouped pipe becomes ready.
pub struct Waiter {
    process: isize,
}

impl Waiter {
    pub fn new(exit: Option<sys::Fd>, pipes: [sys::Fd; 3]) -> Option<Waiter> {
        let process = exit?;
        for fd in pipes {
            if adopted::is_adopted(fd) {
                adopted::group(fd, process);
            }
        }
        Some(Waiter { process })
    }

    /// The process handle fires once; later parks wake on the pipes alone.
    pub fn exited(&mut self) {}

    pub fn park(&self, timeout_ns: i64) {
        // SAFETY: the process handle stays open while `run` holds the child, and the child's
        // drop ends the watch.
        if unsafe { ms_rt::glue::object::wait(self.process, timeout_ns) }.is_none() {
            // The process cannot be watched: check again after a short park.
            ms_rt::glue::task_sleep(2_000_000);
        }
    }
}
