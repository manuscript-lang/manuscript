//! Private HTTP member bootstrap. A listener crosses once, before any ordinary
//! control-channel reader starts. This object must be owned by a cleanup scope
//! before `send_listener` or `receive_listener`: those operations can park.

use crate::error::HttpErr;
use ms_std_process::fork::IpcLink;
use ms_std_process::ipc::Link;
use socket2::Socket;
use std::cell::{Cell, OnceCell, RefCell};

pub mod launch;

/// Owns the unsplit endpoint, then the framed-control endpoint, throughout startup.
/// Cancellation can abandon a Rust stack frame; all persistent allocations and
/// OS references therefore live here, in the caller's cleanup-owned object.
pub struct Bootstrap {
    link: RefCell<Option<Link>>,
    control: OnceCell<IpcLink>,
    started: Cell<bool>,
    transferred: Cell<bool>,
    socket: RefCell<Option<Socket>>,
    frame: RefCell<Vec<u8>>,
    frame_length: Cell<Option<usize>>,
    writing: Cell<bool>,
    closed: Cell<bool>,
    #[cfg(windows)]
    pending: RefCell<Vec<u8>>,
}

impl Bootstrap {
    pub fn new(link: Link) -> Self {
        Self {
            link: RefCell::new(Some(link)),
            control: OnceCell::new(),
            started: Cell::new(false),
            transferred: Cell::new(false),
            socket: RefCell::new(None),
            frame: RefCell::new(Vec::new()),
            frame_length: Cell::new(None),
            writing: Cell::new(false),
            closed: Cell::new(false),
            #[cfg(windows)]
            pending: RefCell::new(Vec::new()),
        }
    }

    fn begin(&self) -> Result<(), HttpErr> {
        if self.closed.get() {
            return Err(HttpErr::Closed);
        }
        if self.started.replace(true) {
            return Err(HttpErr::InvalidInput);
        }
        Ok(())
    }

    /// Workers move their listener directly into the new isolate; only the
    /// endpoint needs splitting. No arena-owned value crosses this constructor.
    pub fn local(link: Link, socket: Option<Socket>) -> Result<Self, HttpErr> {
        let bootstrap = Self::new(link);
        bootstrap.begin()?;
        *bootstrap.socket.borrow_mut() = socket;
        bootstrap.split()?;
        bootstrap.transferred.set(true);
        Ok(bootstrap)
    }

    /// Bounded bootstrap/control framing, shared by worker and process members.
    /// Each endpoint has one writer; normal control begins after configuration.
    pub fn write(&self, bytes: &[u8]) -> Result<(), HttpErr> {
        if bytes.len() > 16 * 1024 * 1024 {
            return Err(HttpErr::LimitExceeded);
        }
        let channel = self.control()?;
        // A failed or cancelled partial write poisons this direction. In particular,
        // longjmp leaves this flag set, so a later call cannot append a new frame.
        if self.writing.replace(true) {
            return Err(HttpErr::Closed);
        }
        let length = (bytes.len() as u32).to_be_bytes();
        if !channel.write(&length) || !channel.write(bytes) {
            return Err(HttpErr::Closed);
        }
        self.writing.set(false);
        Ok(())
    }

    /// Reads one bounded frame. Partial input remains owned here during waits
    /// and cancellation, rather than leaking a stack-local Vec through longjmp.
    pub fn read(&self) -> Result<Vec<u8>, HttpErr> {
        let channel = self.control()?;
        loop {
            let target = self.frame_length.get().unwrap_or(4);
            let received = self.frame.borrow().len();
            if received < target {
                let chunk = channel.read((target - received) as i64);
                if chunk.is_empty() {
                    return Err(HttpErr::Closed);
                }
                self.frame.borrow_mut().extend_from_slice(&chunk);
                continue;
            }
            if self.frame_length.get().is_some() {
                self.frame_length.set(None);
                return Ok(self.frame.take());
            }
            let length = {
                let frame = self.frame.borrow();
                u32::from_be_bytes(
                    frame
                        .as_slice()
                        .try_into()
                        .map_err(|_| HttpErr::InvalidData)?,
                ) as usize
            };
            if length > 16 * 1024 * 1024 {
                return Err(HttpErr::LimitExceeded);
            }
            self.frame.borrow_mut().clear();
            self.frame_length.set(Some(length));
        }
    }

    fn split(&self) -> Result<(), HttpErr> {
        let link = self.link.borrow_mut().take().ok_or(HttpErr::Closed)?;
        let control = IpcLink::new(link)
            .map_err(|_| HttpErr::Failed("cannot split member control channel".into()))?;
        self.control.set(control).map_err(|_| HttpErr::InvalidInput)
    }

    /// Sends a new OS reference to the child. The sender retains its original.
    /// No control messages may be written until this succeeds.
    pub fn send_listener(&self, socket: &Socket, child: u32) -> Result<(), HttpErr> {
        self.begin()?;
        #[cfg(unix)]
        {
            use std::os::fd::AsFd;
            let _ = child;
            // SAFETY: begin allows only one operation. The endpoint stays in this object
            // until the operation returns; no RefCell guard survives a cancellable wait.
            let link = unsafe { &*self.link.as_ptr() }
                .as_ref()
                .ok_or(HttpErr::Closed)?;
            link.send_descriptor(socket.as_fd())
                .map_err(|_| HttpErr::Failed("cannot send member listener".into()))?;
            self.split()?;
        }
        #[cfg(windows)]
        {
            *self.pending.borrow_mut() = crate::sys::export_listener(socket, child)
                .map_err(|e| HttpErr::Failed(format!("cannot duplicate member listener: {e}")))?;
            self.split()?;
            // SAFETY: pending is initialized before the write and unchanged until it returns.
            let bytes = unsafe { &*self.pending.as_ptr() };
            if !self.channel()?.write(bytes) {
                return Err(HttpErr::Closed);
            }
            self.pending.borrow_mut().clear();
        }
        self.transferred.set(true);
        Ok(())
    }

    /// Adopts exactly one reference, retaining ownership here until the server takes it.
    /// Ordinary channel reads begin only after this returns successfully.
    pub fn receive_listener(&self) -> Result<(), HttpErr> {
        self.begin()?;
        #[cfg(unix)]
        {
            // SAFETY: as in send_listener; ownership stays in this object across parks.
            let link = unsafe { &*self.link.as_ptr() }
                .as_ref()
                .ok_or(HttpErr::Closed)?;
            let descriptor = link
                .receive_descriptor()
                .map_err(|_| HttpErr::InvalidData)?;
            let socket = Socket::from(descriptor);
            socket
                .set_nonblocking(true)
                .map_err(|e| HttpErr::Failed(e.to_string()))?;
            *self.socket.borrow_mut() = Some(socket);
            self.split()?;
        }
        #[cfg(windows)]
        {
            self.split()?;
            let length = size_of::<windows_sys::Win32::Networking::WinSock::WSAPROTOCOL_INFOW>();
            while self.pending.borrow().len() < length {
                let remaining = length - self.pending.borrow().len();
                let bytes = self.channel()?.read(remaining as i64);
                if bytes.is_empty() {
                    return Err(HttpErr::Closed);
                }
                self.pending.borrow_mut().extend_from_slice(&bytes);
            }
            let socket = crate::sys::import_listener(&self.pending.borrow())
                .map_err(|e| HttpErr::Failed(format!("cannot adopt member listener: {e}")))?;
            *self.socket.borrow_mut() = Some(socket);
            self.pending.borrow_mut().clear();
        }
        self.transferred.set(true);
        Ok(())
    }

    /// The normal control endpoint, available only after listener transfer.
    pub fn control(&self) -> Result<&IpcLink, HttpErr> {
        if self.closed.get() || !self.transferred.get() {
            return Err(HttpErr::Closed);
        }
        self.channel()
    }

    fn channel(&self) -> Result<&IpcLink, HttpErr> {
        self.control.get().ok_or(HttpErr::Closed)
    }

    /// Moves the adopted listener into its member-local HTTP server, exactly once.
    pub fn take_listener(&self) -> Result<Socket, HttpErr> {
        if !self.transferred.get() {
            return Err(HttpErr::Closed);
        }
        self.socket.borrow_mut().take().ok_or(HttpErr::Closed)
    }

    /// Called by the owning scope after its I/O task scope has joined.
    pub fn close(&self) {
        if self.closed.replace(true) {
            return;
        }
        if let Some(control) = self.control.get() {
            control.close();
        }
        self.link.borrow_mut().take();
        self.socket.borrow_mut().take();
        self.frame.borrow_mut().clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_std_process::{command, ipc};
    use std::io::{Read, Write};

    #[test]
    #[ignore = "started by listener_reference_crosses_a_process_boundary"]
    fn listener_child() {
        let bootstrap = Bootstrap::new(Link::adopt().unwrap().unwrap());
        bootstrap.receive_listener().unwrap();
        let listener = bootstrap.take_listener().unwrap();
        assert!(bootstrap.take_listener().is_err());
        listener.set_nonblocking(false).unwrap();
        assert!(bootstrap.control().unwrap().write(b"R"));
        let (socket, _) = listener.accept().unwrap();
        let mut stream = std::net::TcpStream::from(socket);
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(5)))
            .unwrap();
        let mut byte = [0];
        stream.read_exact(&mut byte).unwrap();
        assert_eq!(byte, *b"?");
        stream.write_all(b"member").unwrap();
    }

    #[test]
    fn listener_reference_crosses_a_process_boundary() {
        crate::http::server::serialize_tests();
        let net = crate::net::Network::new_root();
        let listener = net.listen_tcp("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap().as_socket().unwrap();
        let (link, end) = ipc::pair().unwrap();
        let bootstrap = Bootstrap::new(link);
        assert!(bootstrap.control().is_err());
        let exe = std::env::current_exe().unwrap();
        let args = ["http::group::tests::listener_child", "--exact", "--ignored"]
            .map(|arg| arg.as_bytes().to_vec());
        let mut child = command::spawn_isolated(
            exe.as_os_str().as_encoded_bytes(),
            &args,
            [
                command::STDIO_NULL,
                command::STDIO_INHERIT,
                command::STDIO_INHERIT,
            ],
            Some(&end),
            &[],
        )
        .unwrap();
        drop(end);
        bootstrap
            .send_listener(&listener, child.child.id())
            .unwrap();
        assert!(
            bootstrap
                .send_listener(&listener, child.child.id())
                .is_err()
        );
        drop(listener);
        assert_eq!(bootstrap.control().unwrap().read(1), b"R");
        let mut stream =
            std::net::TcpStream::connect_timeout(&address, std::time::Duration::from_secs(5))
                .unwrap();
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(5)))
            .unwrap();
        stream.write_all(b"?").unwrap();
        let mut response = [0; 6];
        stream.read_exact(&mut response).unwrap();
        assert_eq!(&response, b"member");
        assert_eq!(child.wait(Some(5_000_000_000)).unwrap(), 0);
        child.closed = true;
    }
}
