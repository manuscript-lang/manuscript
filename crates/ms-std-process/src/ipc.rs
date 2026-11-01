//! The IPC pipe between a parent and a child it starts (`proposals/child-processes.md`): a
//! dedicated duplex byte stream beside the standard streams, as Node's `NODE_CHANNEL_FD`, so the
//! child's own output never mixes with messages. Framing and encoding live in Manuscript
//! (`@std/io/channels.ms`); this module only makes the pipe, hands the child its end, and reads and
//! writes bytes.
//!
//! Unix uses a `socketpair`; the child's end becomes descriptor [`CHILD_FD`]. Windows uses an
//! overlapped named pipe with a random name that only the current user can open: the parent
//! opens both ends and the child inherits its end by handle. Either way the child finds its end
//! through [`ENV`]. Reads and writes park the task until the pipe is ready (the poller on both
//! platforms), with no polling.
use alloc::vec::Vec;
use ms_rt_abi::STATUS_FAILED;
use ms_std_fs::err::{Fail, Res, describe};

/// The environment variable that names the child's end: a descriptor or handle number.
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

/// One end of the pipe, before it is split into a reader and a writer.
pub struct Link(plat::Link);

/// The child's end before the child starts, held by the parent until `spawn::start` has passed
/// it on.
pub struct ChildEnd {
    pub(crate) end: plat::ChildLink,
}

impl ChildEnd {
    /// The value of [`ENV`] in the child.
    pub fn env_value(&self) -> Vec<u8> {
        self.end.env_value()
    }
}

/// A new pipe: the parent's end and the end to give the child.
pub fn pair() -> Res<(Link, ChildEnd)> {
    let (link, end) = plat::pair().map_err(|e| os_failure("ipc", e))?;
    Ok((Link(link), ChildEnd { end }))
}

/// The reading half of an end.
pub struct Reader(plat::Reader);

/// The writing half of an end.
pub struct Writer(plat::Writer);

/// Whether this process was started with an end by `ProcessGroup.spawn`.
static STARTED_BY_GROUP: core::sync::atomic::AtomicBool =
    core::sync::atomic::AtomicBool::new(false);

/// Whether this process is a `ProcessGroup` child, so its parent's kill of its group must reach
/// everything it starts.
pub fn started_by_group() -> bool {
    STARTED_BY_GROUP.load(core::sync::atomic::Ordering::Relaxed)
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
        STARTED_BY_GROUP.store(true, core::sync::atomic::Ordering::Relaxed);
        let link = plat::adopt(value.as_encoded_bytes()).map_err(|e| os_failure("ipc", e))?;
        Ok(Some(Link(link)))
    }

    /// Splits the end into halves that a reading task and a writing task use at the same time.
    pub fn split(self) -> Res<(Reader, Writer)> {
        let (r, w) = self.0.split().map_err(|e| os_failure("ipc", e))?;
        Ok((Reader(r), Writer(w)))
    }
}

impl Reader {
    /// Up to `buf.len()` bytes, parking until some arrive; 0 once the other process is gone and
    /// everything it sent was read.
    pub fn read(&mut self, buf: &mut [u8]) -> Res<usize> {
        self.0.read(buf).map_err(|e| os_failure("ipc read", e))
    }
}

impl Writer {
    /// Writes all of `data`, parking while the pipe is full. `Failed` once the other process is
    /// gone.
    pub fn write(&mut self, data: &[u8]) -> Res<()> {
        self.0.write(data).map_err(|e| os_failure("ipc write", e))
    }
}

#[cfg(unix)]
mod plat {
    use super::CHILD_FD;
    use alloc::vec::Vec;
    use ms_rt::glue::{WAIT_READ, WAIT_WRITE, poll_cancel, task_wait_fd};

    /// An open socket, closed on drop.
    pub struct Link(i32);

    /// The child's socket in the parent, closed once the child has its copy.
    pub struct ChildLink(pub(crate) i32);

    /// A reader and a writer hold separate descriptors on one socket, so each parks on its own.
    pub struct Reader(Link);
    pub struct Writer(Link);

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
            // SAFETY: the descriptor is ours and closed once.
            unsafe { libc::close(self.0) };
        }
    }

    fn errno() -> i32 {
        std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
    }

    fn cloexec(fd: i32) {
        // SAFETY: plain fcntl call on an open descriptor.
        unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) };
    }

    /// Non-blocking mode, so reads and writes park the task instead of the thread; on Apple
    /// platforms (no `MSG_NOSIGNAL`) a write to a gone peer is `EPIPE`, not SIGPIPE.
    fn nonblocking(fd: i32) {
        // SAFETY: plain fcntl and setsockopt calls on an open descriptor.
        unsafe {
            let flags = libc::fcntl(fd, libc::F_GETFL);
            libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
            #[cfg(target_vendor = "apple")]
            {
                let on: libc::c_int = 1;
                libc::setsockopt(
                    fd,
                    libc::SOL_SOCKET,
                    libc::SO_NOSIGPIPE,
                    (&on as *const libc::c_int).cast(),
                    core::mem::size_of::<libc::c_int>() as libc::socklen_t,
                );
            }
        }
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
        pub fn split(self) -> Result<(Reader, Writer), i32> {
            // SAFETY: plain system call on an open descriptor.
            let second = unsafe { libc::fcntl(self.0, libc::F_DUPFD_CLOEXEC, 0) };
            if second < 0 {
                return Err(errno());
            }
            nonblocking(self.0);
            Ok((Reader(self), Writer(Link(second))))
        }
    }

    impl Reader {
        pub fn read(&mut self, buf: &mut [u8]) -> Result<usize, i32> {
            loop {
                poll_cancel();
                // SAFETY: `buf` is writable for its length.
                let n = unsafe { libc::read((self.0).0, buf.as_mut_ptr().cast(), buf.len()) };
                if n >= 0 {
                    return Ok(n as usize);
                }
                match errno() {
                    libc::EAGAIN | libc::EINTR => {
                        task_wait_fd((self.0).0, WAIT_READ, -1);
                    }
                    libc::ECONNRESET => return Ok(0),
                    e => return Err(e),
                }
            }
        }
    }

    impl Writer {
        pub fn write(&mut self, mut data: &[u8]) -> Result<(), i32> {
            #[cfg(any(target_os = "linux", target_os = "android"))]
            let flags = libc::MSG_NOSIGNAL;
            #[cfg(not(any(target_os = "linux", target_os = "android")))]
            let flags = 0;
            while !data.is_empty() {
                poll_cancel();
                // SAFETY: `data` is readable for its length.
                let n = unsafe { libc::send((self.0).0, data.as_ptr().cast(), data.len(), flags) };
                if n >= 0 {
                    data = &data[n as usize..];
                    continue;
                }
                match errno() {
                    libc::EAGAIN | libc::EINTR => {
                        task_wait_fd((self.0).0, WAIT_WRITE, -1);
                    }
                    e => return Err(e),
                }
            }
            Ok(())
        }
    }
}

#[cfg(windows)]
mod plat {
    use alloc::rc::Rc;
    use alloc::vec::Vec;
    use core::ptr::null_mut;
    use ms_rt::glue::pipe;
    use windows_sys::Win32::Foundation::{
        CloseHandle, GetLastError, HANDLE, HANDLE_FLAG_INHERIT, SetHandleInformation,
    };

    /// An overlapped pipe handle, closed on drop until it is handed to the runtime poller.
    pub struct Link(HANDLE);

    /// The child's end, opened by the parent; `start` lets the child inherit it.
    pub struct ChildLink(pub(crate) Link);

    /// Both halves share the handle the poller adopted; the last one closes it.
    struct Adopted(isize);
    pub struct Reader(Rc<Adopted>);
    pub struct Writer(Rc<Adopted>);

    impl Drop for Adopted {
        fn drop(&mut self) {
            pipe::close(self.0);
        }
    }

    impl ChildLink {
        pub fn env_value(&self) -> Vec<u8> {
            alloc::format!("{}", (self.0).0 as usize).into_bytes()
        }

        /// Lets the next child started inherit the handle, at the same value; `start` turns it
        /// off again once the child started.
        pub fn inherit(&self, on: bool) -> Result<(), i32> {
            let flag = if on { HANDLE_FLAG_INHERIT } else { 0 };
            // SAFETY: plain call on our open handle.
            if unsafe { SetHandleInformation(self.0.0, HANDLE_FLAG_INHERIT, flag) } == 0 {
                return Err(last_error());
            }
            Ok(())
        }
    }

    impl Drop for Link {
        fn drop(&mut self) {
            if !self.0.is_null() {
                // SAFETY: the handle is ours and closed once.
                unsafe { CloseHandle(self.0) };
            }
        }
    }

    fn last_error() -> i32 {
        // SAFETY: plain query.
        unsafe { GetLastError() as i32 }
    }

    pub fn pair() -> Result<(Link, ChildLink), i32> {
        let (mut server, mut client) = crate::command::duplex_pipe()?;
        Ok((
            Link(server.take() as HANDLE),
            ChildLink(Link(client.take() as HANDLE)),
        ))
    }

    pub fn adopt(value: &[u8]) -> Result<Link, i32> {
        let handle = core::str::from_utf8(value)
            .ok()
            .and_then(|s| s.parse::<usize>().ok())
            .ok_or(6)? as HANDLE;
        // So the child's own children do not inherit the pipe.
        // SAFETY: plain call; it fails on a handle that is not open.
        if unsafe { SetHandleInformation(handle, HANDLE_FLAG_INHERIT, 0) } == 0 {
            return Err(last_error());
        }
        Ok(Link(handle))
    }

    impl Link {
        pub fn split(mut self) -> Result<(Reader, Writer), i32> {
            let handle = core::mem::replace(&mut self.0, null_mut());
            // SAFETY: an open overlapped pipe handle, owned by the poller from here on.
            if !unsafe { pipe::adopt(handle as isize) } {
                self.0 = handle;
                return Err(last_error());
            }
            let adopted = Rc::new(Adopted(handle as isize));
            Ok((Reader(adopted.clone()), Writer(adopted)))
        }
    }

    fn os_error(e: std::io::Error) -> i32 {
        e.raw_os_error().unwrap_or(0)
    }

    impl Reader {
        pub fn read(&mut self, buf: &mut [u8]) -> Result<usize, i32> {
            pipe::read(self.0.0, buf).map_err(os_error)
        }
    }

    impl Writer {
        pub fn write(&mut self, data: &[u8]) -> Result<(), i32> {
            pipe::write(self.0.0, data).map_err(os_error)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::StdStream;
    use crate::spawn::start;

    /// The test binary started again runs only this test, which echoes what it reads back
    /// reversed per chunk until the parent's end is gone.
    #[test]
    #[ignore = "run as a child by `bytes_cross_both_ways`"]
    fn ipc_child() {
        let Some(link) = Link::adopt().unwrap() else {
            return;
        };
        assert!(std::env::var_os(ENV).is_none());
        let (mut input, mut output) = link.split().unwrap();
        let mut buf = [0u8; 4096];
        loop {
            let n = input.read(&mut buf).unwrap();
            if n == 0 {
                break;
            }
            buf[..n].reverse();
            output.write(&buf[..n]).unwrap();
        }
    }

    #[test]
    fn bytes_cross_both_ways() {
        #[cfg(unix)]
        let _guard = crate::environment_guard();
        let exe = std::env::current_exe().unwrap();
        let args: Vec<Vec<u8>> = [
            "ipc::tests::ipc_child",
            "--exact",
            "--ignored",
            "--nocapture",
        ]
        .iter()
        .map(|s| s.as_bytes().to_vec())
        .collect();
        let (link, end) = pair().unwrap();
        let mut child = start(
            exe.as_os_str().as_encoded_bytes(),
            &args,
            [StdStream::Null, StdStream::Inherit, StdStream::Inherit],
            Some(&end),
            &[],
        )
        .unwrap();
        drop(end);
        let (mut input, mut output) = link.split().unwrap();
        output.write(b"ping").unwrap();
        let mut buf = [0u8; 16];
        let n = input.read(&mut buf).unwrap();
        assert_eq!(&buf[..n], b"gnip");
        // The child sees end of stream once both halves are closed. On Windows the handle closes
        // when the poller next collects the cancelled read, so wait as a task does, letting the
        // reactor run, rather than blocking the thread.
        drop((input, output));
        while !child.poll() {
            assert!(child.park_until_exit(-1));
        }
        assert_eq!(child.wait(), 0);
    }
}
