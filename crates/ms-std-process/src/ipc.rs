//! The IPC pipe between a parent and a child it starts (`proposals/child-processes.md`): a
//! dedicated duplex byte stream beside the standard streams, as Node's `NODE_CHANNEL_FD`, so the
//! child's own output never mixes with messages. Framing and encoding live in Manuscript
//! (`@std/channels.ms`); this module only makes the pipe, hands the child its end, and gives each
//! side a readable and a writable descriptor for an ordinary `Stream`.
//!
//! Unix uses a `socketpair`; the child's end becomes descriptor [`CHILD_FD`]. Windows uses a
//! named pipe with a random name that only the current user can open; the child opens it by name,
//! so no handle is inherited. Either way the child finds its end through [`ENV`].
use ms_rt_abi::STATUS_FAILED;
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys;

/// The environment variable that names the child's end: a descriptor number or a pipe name.
pub const ENV: &str = "MS_IPC";
/// The descriptor the child's end is moved to on Unix.
#[cfg(unix)]
pub const CHILD_FD: i32 = 3;

fn os_failure(op: &str, e: i32) -> Fail {
    let mut m = op.as_bytes().to_vec();
    m.extend_from_slice(b": ");
    m.extend_from_slice(describe(e).as_bytes());
    Fail {
        status: STATUS_FAILED,
        message: Some(m),
    }
}

/// One end of the pipe.
pub struct Link(plat::Link);

/// The child's end before the child starts, held by the parent until `spawn::start` has passed
/// it on.
pub struct ChildEnd {
    pub(crate) end: plat::ChildLink,
}

impl ChildEnd {
    /// The value of [`ENV`] in the child.
    pub fn env_value(&self) -> alloc::vec::Vec<u8> {
        self.end.env_value()
    }
}

/// A new pipe: the parent's end and the end to give the child.
pub fn pair() -> Res<(Link, ChildEnd)> {
    let (link, end) = plat::pair().map_err(|e| os_failure("ipc", e))?;
    Ok((Link(link), ChildEnd { end }))
}

impl Link {
    /// The child's end named by [`ENV`] in this process, or none when this process was not
    /// started with one. The variable is removed so user code and grandchildren do not see it.
    pub fn adopt() -> Res<Option<Link>> {
        let Some(value) = std::env::var_os(ENV) else {
            return Ok(None);
        };
        // SAFETY: called once from the start path, before user code or other threads read the
        // environment.
        unsafe { std::env::remove_var(ENV) };
        let link = plat::adopt(value.as_encoded_bytes()).map_err(|e| os_failure("ipc", e))?;
        Ok(Some(Link(link)))
    }

    /// Waits until the child has opened its end (Windows; immediate on Unix). `Failed` when the
    /// child exits first.
    pub fn accept(&mut self, child: &mut crate::spawn::Child) -> Res<()> {
        loop {
            match self.0.try_accept() {
                Ok(true) => return Ok(()),
                Ok(false) => {}
                Err(e) => return Err(os_failure("ipc connect", e)),
            }
            if child.poll() {
                return Err(os_failure("ipc connect", 0));
            }
            ms_rt::glue::task_sleep(2_000_000);
        }
    }

    /// A descriptor to read from and one to write to, each owned by the caller (two handles on
    /// the same pipe, so a reader and a writer stream close independently).
    pub fn into_fds(self) -> Res<(sys::Fd, sys::Fd)> {
        self.0.into_fds().map_err(|e| os_failure("ipc", e))
    }
}

#[cfg(unix)]
mod plat {
    use super::CHILD_FD;
    use alloc::vec::Vec;

    /// An open socket, closed on drop.
    pub struct Link(i32);

    /// The child's socket in the parent, closed once the child has its copy.
    pub struct ChildLink(pub(crate) i32);

    impl ChildLink {
        pub fn env_value(&self) -> Vec<u8> {
            alloc::format!("{CHILD_FD}").into_bytes()
        }
    }

    impl Drop for ChildLink {
        fn drop(&mut self) {
            // SAFETY: the descriptor is ours and closed once.
            unsafe { libc::close(self.0) };
        }
    }

    impl Drop for Link {
        fn drop(&mut self) {
            if self.0 >= 0 {
                // SAFETY: the descriptor is ours and closed once.
                unsafe { libc::close(self.0) };
            }
        }
    }

    fn errno() -> i32 {
        std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
    }

    fn cloexec(fd: i32) {
        // SAFETY: plain fcntl call on an open descriptor.
        unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) };
    }

    pub fn pair() -> Result<(Link, ChildLink), i32> {
        let mut fds = [0i32; 2];
        // SAFETY: `fds` has room for two descriptors.
        if unsafe { libc::socketpair(libc::AF_UNIX, libc::SOCK_STREAM, 0, fds.as_mut_ptr()) } != 0 {
            return Err(errno());
        }
        // The child's end stays close-on-exec until `start` moves it to `CHILD_FD`.
        cloexec(fds[0]);
        cloexec(fds[1]);
        Ok((Link(fds[0]), ChildLink(fds[1])))
    }

    pub fn adopt(value: &[u8]) -> Result<Link, i32> {
        let fd = core::str::from_utf8(value)
            .ok()
            .and_then(|s| s.parse::<i32>().ok())
            .filter(|&fd| fd >= 0)
            .ok_or(libc::EBADF)?;
        // SAFETY: plain query.
        if unsafe { libc::fcntl(fd, libc::F_GETFD) } < 0 {
            return Err(errno());
        }
        // So the child's own children do not hold the pipe open.
        cloexec(fd);
        Ok(Link(fd))
    }

    impl Link {
        pub fn try_accept(&mut self) -> Result<bool, i32> {
            Ok(true)
        }

        pub fn into_fds(mut self) -> Result<(i32, i32), i32> {
            // SAFETY: plain system call on an open descriptor.
            let second = unsafe { libc::fcntl(self.0, libc::F_DUPFD_CLOEXEC, 0) };
            if second < 0 {
                return Err(errno());
            }
            let first = core::mem::replace(&mut self.0, -1);
            Ok((first, second))
        }
    }
}

#[cfg(windows)]
mod plat {
    use alloc::vec::Vec;
    use core::ptr::{null, null_mut};
    use windows_sys::Win32::Foundation::{
        CloseHandle, DUPLICATE_SAME_ACCESS, DuplicateHandle, ERROR_NO_DATA, ERROR_PIPE_CONNECTED,
        ERROR_PIPE_LISTENING, GENERIC_READ, GENERIC_WRITE, GetLastError, HANDLE,
        INVALID_HANDLE_VALUE, LocalFree,
    };
    use windows_sys::Win32::Security::Authorization::{
        ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1,
    };
    use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;
    use windows_sys::Win32::Storage::FileSystem::{
        CreateFileW, FILE_FLAG_FIRST_PIPE_INSTANCE, OPEN_EXISTING, PIPE_ACCESS_DUPLEX,
    };
    use windows_sys::Win32::System::Pipes::{
        ConnectNamedPipe, CreateNamedPipeW, PIPE_NOWAIT, PIPE_READMODE_BYTE,
        PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE, PIPE_WAIT, SetNamedPipeHandleState,
    };
    use windows_sys::Win32::System::Threading::GetCurrentProcess;

    const BUFFER: u32 = 64 * 1024;

    /// An open pipe handle, closed on drop. The parent's end is the server, created in
    /// non-blocking mode so `try_accept` answers at once; it is blocking once connected, as the
    /// standard-stream pipes are.
    pub struct Link {
        handle: HANDLE,
        connected: bool,
    }

    /// The pipe's name; the parent's server end already exists.
    pub struct ChildLink(Vec<u16>);

    impl ChildLink {
        pub fn env_value(&self) -> Vec<u8> {
            alloc::string::String::from_utf16_lossy(&self.0[..self.0.len() - 1]).into_bytes()
        }
    }

    impl Drop for Link {
        fn drop(&mut self) {
            if !self.handle.is_null() {
                // SAFETY: the handle is ours and closed once.
                unsafe { CloseHandle(self.handle) };
            }
        }
    }

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

    pub fn pair() -> Result<(Link, ChildLink), i32> {
        let name = alloc::format!(
            r"\\.\pipe\ms-ipc-{}-{:032x}",
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
        let handle = unsafe {
            CreateNamedPipeW(
                wname.as_ptr(),
                PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS,
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
        if handle == INVALID_HANDLE_VALUE {
            return Err(error);
        }
        Ok((
            Link {
                handle,
                connected: false,
            },
            ChildLink(wname),
        ))
    }

    pub fn adopt(value: &[u8]) -> Result<Link, i32> {
        let name = core::str::from_utf8(value).map_err(|_| ERROR_NO_DATA as i32)?;
        let wname = wide(name);
        // SAFETY: `wname` is NUL-terminated.
        let handle = unsafe {
            CreateFileW(
                wname.as_ptr(),
                GENERIC_READ | GENERIC_WRITE,
                0,
                null(),
                OPEN_EXISTING,
                0,
                null_mut(),
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(last_error());
        }
        Ok(Link {
            handle,
            connected: true,
        })
    }

    impl Link {
        pub fn try_accept(&mut self) -> Result<bool, i32> {
            if self.connected {
                return Ok(true);
            }
            // SAFETY: `handle` is an open server end in non-blocking mode.
            let done = unsafe { ConnectNamedPipe(self.handle, null_mut()) } != 0;
            if !done {
                match last_error() as u32 {
                    ERROR_PIPE_CONNECTED => {}
                    ERROR_PIPE_LISTENING => return Ok(false),
                    e => return Err(e as i32),
                }
            }
            self.connected = true;
            let mode = PIPE_READMODE_BYTE | PIPE_WAIT;
            // SAFETY: `handle` is open and `mode` is readable.
            unsafe { SetNamedPipeHandleState(self.handle, &mode, null(), null()) };
            Ok(true)
        }

        pub fn into_fds(mut self) -> Result<(isize, isize), i32> {
            let mut second: HANDLE = null_mut();
            // SAFETY: duplicates our own open handle into this process.
            let ok = unsafe {
                let me = GetCurrentProcess();
                DuplicateHandle(
                    me,
                    self.handle,
                    me,
                    &mut second,
                    0,
                    0,
                    DUPLICATE_SAME_ACCESS,
                )
            };
            if ok == 0 {
                return Err(last_error());
            }
            let first = core::mem::replace(&mut self.handle, null_mut());
            Ok((first as isize, second as isize))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::StdStream;
    use crate::spawn::start;
    use ms_std_fs::stream::Stream;

    /// The test binary started again runs only this test, which echoes what it reads back
    /// reversed per chunk until the parent closes its end.
    #[test]
    #[ignore = "run as a child by `bytes_cross_both_ways`"]
    fn ipc_child() {
        let Some(link) = Link::adopt().unwrap() else {
            return;
        };
        assert!(std::env::var_os(ENV).is_none());
        let (r, w) = link.into_fds().unwrap();
        let (mut input, mut output) = (Stream::new(r, true, b"ipc"), Stream::new(w, true, b"ipc"));
        while let Some(mut chunk) = input.read(None).unwrap() {
            chunk.reverse();
            output.write(&chunk).unwrap();
        }
    }

    #[test]
    fn bytes_cross_both_ways() {
        #[cfg(unix)]
        let _guard = crate::environment_guard();
        let exe = std::env::current_exe().unwrap();
        let args: alloc::vec::Vec<alloc::vec::Vec<u8>> = [
            "ipc::tests::ipc_child",
            "--exact",
            "--ignored",
            "--nocapture",
        ]
        .iter()
        .map(|s| s.as_bytes().to_vec())
        .collect();
        let (mut link, end) = pair().unwrap();
        let mut child = start(
            exe.as_os_str().as_encoded_bytes(),
            &args,
            [StdStream::Null, StdStream::Inherit, StdStream::Inherit],
            Some(&end),
        )
        .unwrap();
        drop(end);
        link.accept(&mut child).unwrap();
        let (r, w) = link.into_fds().unwrap();
        let (mut input, mut output) = (Stream::new(r, true, b"ipc"), Stream::new(w, true, b"ipc"));
        output.write(b"ping").unwrap();
        assert_eq!(input.read(None).unwrap().unwrap(), b"gnip");
        // Both handles are one pipe: the child sees end of file once both are closed.
        output.close().unwrap();
        input.close().unwrap();
        assert_eq!(child.wait(), 0);
    }
}
