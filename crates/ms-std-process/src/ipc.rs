//! The IPC pipe between a parent and a child it starts (`proposals/child-processes.md`): a
//! dedicated duplex byte stream beside the standard streams, as Node's `NODE_CHANNEL_FD`, so the
//! child's own output never mixes with messages. Framing and encoding live in Manuscript
//! (`@std/channels.ms`); this module only makes the pipe, hands the child its end, and reads and
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

// SAFETY: an unsplit Link owns an OS handle with no attached poller or arena values.
// The split reader/writer remain isolate-local and deliberately do not gain Send.
unsafe impl Send for Link {}

/// Native parent-death monitor for a separately supervised Unix process group.
/// Dropping it disarms and joins the native monitor before normal completion is announced.
/// The join waits at most one polling interval (100 ms), apart from OS scheduling.
#[cfg(unix)]
pub struct ParentWatchdog {
    stopped: std::sync::Arc<std::sync::atomic::AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
}

#[cfg(unix)]
impl Drop for ParentWatchdog {
    fn drop(&mut self) {
        self.stopped
            .store(true, std::sync::atomic::Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// The child's end before the child starts, held by the parent until `spawn::start` has passed
/// it on.
pub struct ChildEnd {
    pub(crate) end: plat::ChildLink,
}

impl ChildEnd {
    /// Moves the unsplit endpoint to another isolate in this process without inheritance.
    pub fn into_local(self) -> Link {
        Link(self.end.into_local())
    }
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

    /// Watches parent endpoint disappearance independently of the language scheduler.
    /// The caller must be the leader of an independently supervised process group.
    #[cfg(unix)]
    /// EOF first gives the language control task `grace` to drain. The monitor then
    /// kills the owned process group even if application code cannot yield. Keep the
    /// parent endpoint open until the member has disarmed this monitor and reported done.
    pub fn watch_parent(&self, grace: std::time::Duration) -> Res<ParentWatchdog> {
        self.0
            .watch_parent(grace)
            .map_err(|e| os_failure("parent watchdog", e))
    }

    /// Sends one owned-reference duplicate during native bootstrap, before ordinary reads.
    /// This is a runtime facility, not an application channel operation.
    #[cfg(unix)]
    pub fn send_descriptor(&self, descriptor: std::os::fd::BorrowedFd<'_>) -> Res<()> {
        self.0
            .send_descriptor(descriptor)
            .map_err(|e| os_failure("ipc descriptor send", e))
    }

    /// Receives exactly one close-on-exec descriptor before splitting the stream.
    /// Malformed or truncated messages close every received descriptor and fail.
    #[cfg(unix)]
    pub fn receive_descriptor(&self) -> Res<std::os::fd::OwnedFd> {
        self.0
            .receive_descriptor()
            .map_err(|e| os_failure("ipc descriptor receive", e))
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
        pub fn into_local(self) -> Link {
            let this = core::mem::ManuallyDrop::new(self);
            Link(this.0)
        }
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
        pub fn watch_parent(
            &self,
            grace: std::time::Duration,
        ) -> Result<super::ParentWatchdog, i32> {
            use std::os::fd::{AsRawFd, BorrowedFd};
            use std::sync::{
                Arc,
                atomic::{AtomicBool, Ordering},
            };
            // SAFETY: plain process identity queries.
            let pid = unsafe { libc::getpid() };
            // SAFETY: plain query of this process's group identity.
            if unsafe { libc::getpgrp() } != pid {
                return Err(libc::EINVAL);
            }
            // SAFETY: this Link owns the descriptor for this borrowing operation.
            let descriptor =
                rustix::io::fcntl_dupfd_cloexec(unsafe { BorrowedFd::borrow_raw(self.0) }, 0)
                    .map_err(|e| e.raw_os_error())?;
            let stopped = Arc::new(AtomicBool::new(false));
            let flag = stopped.clone();
            let thread = std::thread::Builder::new()
                .name("ms-parent-watch".into())
                .stack_size(256 << 10)
                .spawn(move || {
                    let mut watched = libc::pollfd {
                        fd: descriptor.as_raw_fd(),
                        events: 0,
                        revents: 0,
                    };
                    while !flag.load(Ordering::Acquire) {
                        // SAFETY: an owned descriptor and initialized poll record; no runtime state is used.
                        let ready = unsafe { libc::poll(&mut watched, 1, 100) };
                        if ready > 0
                            && watched.revents & (libc::POLLHUP | libc::POLLERR | libc::POLLNVAL)
                                != 0
                        {
                            let lost = std::time::Instant::now();
                            while !flag.load(Ordering::Acquire) && lost.elapsed() < grace {
                                std::thread::sleep(
                                    (grace - lost.elapsed().min(grace))
                                        .min(std::time::Duration::from_millis(100)),
                                );
                            }
                            if !flag.load(Ordering::Acquire) {
                                // SAFETY: this process owns the group. Parent death must also stop stuck user code and its descendants.
                                unsafe {
                                    libc::kill(-pid, libc::SIGKILL);
                                    libc::_exit(70);
                                }
                            }
                            return;
                        }
                    }
                })
                .map_err(|e| e.raw_os_error().unwrap_or(libc::EAGAIN))?;
            Ok(super::ParentWatchdog {
                stopped,
                thread: Some(thread),
            })
        }

        pub fn send_descriptor(&self, descriptor: std::os::fd::BorrowedFd<'_>) -> Result<(), i32> {
            use core::mem::MaybeUninit;
            use rustix::net::{SendAncillaryBuffer, SendAncillaryMessage, SendFlags, sendmsg};
            use std::io::IoSlice;
            use std::os::fd::BorrowedFd;
            nonblocking(self.0);
            // SAFETY: this Link owns the descriptor throughout the operation.
            let socket = unsafe { BorrowedFd::borrow_raw(self.0) };
            let mut space = [MaybeUninit::uninit(); rustix::cmsg_space!(ScmRights(1))];
            let descriptors = [descriptor];
            let mut control = SendAncillaryBuffer::new(&mut space);
            if !control.push(SendAncillaryMessage::ScmRights(&descriptors)) {
                return Err(libc::EINVAL);
            }
            #[cfg(any(target_os = "linux", target_os = "android"))]
            let flags = SendFlags::NOSIGNAL;
            #[cfg(not(any(target_os = "linux", target_os = "android")))]
            let flags = SendFlags::empty();
            loop {
                poll_cancel();
                match sendmsg(socket, &[IoSlice::new(b"L")], &mut control, flags) {
                    Ok(1) => return Ok(()),
                    Ok(_) => return Err(libc::EPIPE),
                    Err(rustix::io::Errno::INTR) => continue,
                    Err(rustix::io::Errno::AGAIN) => {
                        task_wait_fd(self.0, WAIT_WRITE, -1);
                    }
                    Err(error) => return Err(error.raw_os_error()),
                }
            }
        }

        pub fn receive_descriptor(&self) -> Result<std::os::fd::OwnedFd, i32> {
            use core::mem::MaybeUninit;
            use rustix::net::{
                RecvAncillaryBuffer, RecvAncillaryMessage, RecvFlags, ReturnFlags, recvmsg,
            };
            use std::io::IoSliceMut;
            use std::os::fd::BorrowedFd;
            nonblocking(self.0);
            // SAFETY: this Link owns the descriptor throughout the operation.
            let socket = unsafe { BorrowedFd::borrow_raw(self.0) };
            let mut space = [MaybeUninit::uninit(); rustix::cmsg_space!(ScmRights(8))];
            let mut control = RecvAncillaryBuffer::new(&mut space);
            let mut marker = [0u8];
            #[cfg(any(target_os = "linux", target_os = "android"))]
            let flags = RecvFlags::CMSG_CLOEXEC;
            #[cfg(not(any(target_os = "linux", target_os = "android")))]
            let flags = RecvFlags::empty();
            let message = loop {
                poll_cancel();
                match recvmsg(
                    socket,
                    &mut [IoSliceMut::new(&mut marker)],
                    &mut control,
                    flags,
                ) {
                    Ok(message) => break message,
                    Err(rustix::io::Errno::INTR) => continue,
                    Err(rustix::io::Errno::AGAIN) => {
                        task_wait_fd(self.0, WAIT_READ, -1);
                    }
                    Err(error) => return Err(error.raw_os_error()),
                }
            };
            let mut received = Vec::new();
            for message in control.drain() {
                if let RecvAncillaryMessage::ScmRights(descriptors) = message {
                    received.extend(descriptors);
                }
            }
            if message.bytes != 1
                || marker != *b"L"
                || message
                    .flags
                    .intersects(ReturnFlags::CTRUNC | ReturnFlags::TRUNC)
                || received.len() != 1
            {
                return Err(libc::EINVAL);
            }
            let descriptor = received.pop().unwrap();
            rustix::io::fcntl_setfd(&descriptor, rustix::io::FdFlags::CLOEXEC)
                .map_err(|e| e.raw_os_error())?;
            Ok(descriptor)
        }

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

    #[cfg(test)]
    mod descriptor_tests {
        use super::*;
        use core::mem::MaybeUninit;
        use rustix::net::{SendAncillaryBuffer, SendAncillaryMessage, SendFlags, sendmsg};
        use std::io::{IoSlice, Read, Write};
        use std::os::fd::{AsFd, BorrowedFd};
        use std::os::unix::net::UnixStream;
        use std::time::Duration;

        #[test]
        fn malformed_rights_close_every_received_reference() {
            for (count, marker) in [(1, b"?"), (2, b"L"), (16, b"L")] {
                let (sender, receiver) = pair().unwrap();
                let receiver = receiver.into_local();
                let (mut original, mut peer) = UnixStream::pair().unwrap();
                peer.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
                let descriptors = vec![original.as_fd(); count];
                let mut space = [MaybeUninit::uninit(); rustix::cmsg_space!(ScmRights(16))];
                let mut ancillary = SendAncillaryBuffer::new(&mut space);
                assert!(ancillary.push(SendAncillaryMessage::ScmRights(&descriptors)));
                // SAFETY: sender owns this socket until the sendmsg call returns.
                let socket = unsafe { BorrowedFd::borrow_raw(sender.0) };
                assert_eq!(
                    sendmsg(
                        socket,
                        &[IoSlice::new(marker)],
                        &mut ancillary,
                        SendFlags::empty()
                    )
                    .unwrap(),
                    1
                );
                assert!(receiver.receive_descriptor().is_err());
                drop(descriptors);
                // Rejection must not close the sender's original, and must close all installed copies.
                peer.write_all(b"x").unwrap();
                let mut byte = [0];
                original.read_exact(&mut byte).unwrap();
                assert_eq!(byte, *b"x");
                drop(original);
                assert_eq!(
                    peer.read(&mut byte).unwrap(),
                    0,
                    "received descriptor leaked: {count}"
                );
            }
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
        pub fn into_local(self) -> Link {
            self.0
        }
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

    #[cfg(unix)]
    #[test]
    fn descriptor_transfer_owns_a_close_on_exec_reference() {
        use std::os::fd::AsFd;
        let (sender, receiver) = pair().unwrap();
        let receiver = receiver.into_local();
        let file = std::fs::File::open("/dev/null").unwrap();
        sender.send_descriptor(file.as_fd()).unwrap();
        drop(file);
        let received = receiver.receive_descriptor().unwrap();
        assert!(
            rustix::io::fcntl_getfd(&received)
                .unwrap()
                .contains(rustix::io::FdFlags::CLOEXEC)
        );
        drop(sender);
        let mut file = std::fs::File::from(received);
        assert_eq!(std::io::Read::read(&mut file, &mut [0; 1]).unwrap(), 0);
    }

    #[cfg(unix)]
    #[test]
    fn descriptor_transfer_rejects_missing_rights_and_eof() {
        for marker in [b"L".as_slice(), b"?".as_slice(), b"".as_slice()] {
            let (sender, receiver) = pair().unwrap();
            let receiver = receiver.into_local();
            let (reader, mut writer) = sender.split().unwrap();
            writer.write(marker).unwrap();
            drop((reader, writer));
            assert!(receiver.receive_descriptor().is_err());
        }
    }

    #[cfg(unix)]
    #[test]
    #[ignore = "run as a child by descriptor_crosses_process_boundary"]
    fn descriptor_child() {
        let link = Link::adopt().unwrap().unwrap();
        let descriptor = link.receive_descriptor().unwrap();
        let mut file = std::fs::File::from(descriptor);
        let mut bytes = [1; 4];
        std::io::Read::read_exact(&mut file, &mut bytes).unwrap();
        assert_eq!(bytes, [0; 4]);
        let (_, mut output) = link.split().unwrap();
        output.write(b"adopted").unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn descriptor_crosses_process_boundary() {
        use std::os::fd::AsFd;
        let _guard = crate::environment_guard();
        let exe = std::env::current_exe().unwrap();
        let args = ["ipc::tests::descriptor_child", "--exact", "--ignored"]
            .map(|arg| arg.as_bytes().to_vec());
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
        let file = std::fs::File::open("/dev/zero").unwrap();
        link.send_descriptor(file.as_fd()).unwrap();
        drop(file);
        let (mut input, output) = link.split().unwrap();
        let mut received = Vec::new();
        let mut bytes = [0; 7];
        while received.len() < 7 {
            let n = input.read(&mut bytes).unwrap();
            assert_ne!(n, 0);
            received.extend_from_slice(&bytes[..n]);
        }
        assert_eq!(received, b"adopted");
        drop((input, output));
        while !child.poll() {
            assert!(child.park_until_exit(-1));
        }
        assert_eq!(child.wait(), 0);
    }

    #[cfg(unix)]
    #[test]
    #[ignore = "run as a child by parent_loss_stops_an_uncooperative_member"]
    fn watched_child() {
        let link = Link::adopt().unwrap().unwrap();
        let _watch = link
            .watch_parent(std::time::Duration::from_millis(30))
            .unwrap();
        let (_, mut output) = link.split().unwrap();
        output.write(b"R").unwrap();
        // No Manuscript scheduler progress: the native watchdog must still terminate us.
        loop {
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }

    #[cfg(unix)]
    #[test]
    #[ignore = "run as a child by disarming_parent_watch_precedes_normal_completion"]
    fn disarmed_child() {
        let link = Link::adopt().unwrap().unwrap();
        let watch = link
            .watch_parent(std::time::Duration::from_millis(30))
            .unwrap();
        drop(watch);
        let (_, mut output) = link.split().unwrap();
        output.write(b"R").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(200));
    }

    #[cfg(unix)]
    fn parent_loss_case(name: &str, expected: i64) {
        let _guard = crate::environment_guard();
        let exe = std::env::current_exe().unwrap();
        let args = [name, "--exact", "--ignored"].map(|arg| arg.as_bytes().to_vec());
        let (link, end) = pair().unwrap();
        let mut child = crate::spawn::start_config(
            exe.as_os_str().as_encoded_bytes(),
            &args,
            [StdStream::Null, StdStream::Inherit, StdStream::Inherit],
            Some(&end),
            &[],
            true,
        )
        .unwrap();
        drop(end);
        let (mut input, output) = link.split().unwrap();
        assert_eq!(input.read(&mut [0; 1]).unwrap(), 1);
        drop((input, output));
        let until = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while !child.poll() && std::time::Instant::now() < until {
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        let completed = child.poll();
        if !completed {
            child.signal(true);
        }
        let status = child.wait();
        assert!(completed, "parent-loss monitor did not stop the child");
        assert_eq!(status, expected);
    }

    #[cfg(unix)]
    #[test]
    fn parent_loss_stops_an_uncooperative_member() {
        parent_loss_case("ipc::tests::watched_child", -1);
    }

    #[cfg(unix)]
    #[test]
    fn disarming_parent_watch_precedes_normal_completion() {
        parent_loss_case("ipc::tests::disarmed_child", 0);
    }

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
