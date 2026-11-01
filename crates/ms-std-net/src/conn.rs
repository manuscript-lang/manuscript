//! Stream connections, listeners and datagram sockets.

use crate::error::{IoErr, NetErr, TlsErr, describe_io_error};
use crate::net::{Network, Resource, limit};
use crate::rt;
use crate::sys::{AsSock, Borrowed};
use crate::tls::{self, TlsOptions};
use crate::wait::{Deadline, Interest, Wait, wait_fd};
use ms_rt::fault::with_cleanup;
use socket2::Socket;
use std::cell::{Cell, UnsafeCell};
use std::io::{self, Read, Write};
use std::net::{SocketAddr, UdpSocket};
use std::ops::Deref;

use std::rc::Rc;
use std::sync::Arc;

/// Result of one nonblocking transfer attempt.
pub enum Step {
    /// Bytes moved.
    Done(usize),
    /// End of stream (reads only).
    Eof,
    /// Retry once the descriptor is readable.
    WantRead,
    /// Retry once the descriptor is writable.
    WantWrite,
    Err(io::Error),
}

/// Peer certificates and negotiation results of a TLS connection.
#[derive(Clone, Debug, Default)]
pub struct TlsDetails {
    pub version: i64,
    pub cipher_suite: i64,
    pub alpn: String,
    pub peer_certificates: Vec<Vec<u8>>,
    pub verified: bool,
}

/// A nonblocking byte stream (plain socket or TLS over one).
pub trait Io {
    fn fd(&self) -> Borrowed<'_>;
    fn read(&self, buf: &mut [u8]) -> Step;
    fn write(&self, data: &[u8]) -> Step;
    /// Completes pending output (TLS records); `Ok(true)` when nothing is left.
    fn flush(&self) -> Step {
        Step::Done(0)
    }
    fn shutdown_write(&self) -> Result<(), NetErr>;
    /// Stops all traffic; the descriptor stays open until `release` or the value is dropped.
    fn shutdown_both(&self);
    /// Closes the descriptor now. Only a closed connection with no operation parked on it may
    /// call this; the stream is unusable afterwards. A stream shared with another owner keeps
    /// it.
    fn release(&self) {}
    fn tls_details(&self) -> Option<TlsDetails> {
        None
    }
    /// Whether a read that filled less than its buffer emptied the socket, so the next
    /// arrival raises a fresh readiness edge without a read that would block first.
    fn short_read_drains(&self) -> bool {
        false
    }
    /// A second stream over a duplicate of the descriptor, closed on its own; `None` when the
    /// stream keeps state of its own (TLS) that a duplicate could not share.
    fn try_clone(&self) -> Option<io::Result<Box<dyn Io>>> {
        None
    }
}

/// A socket that can be closed before its owner is dropped, so a closed connection frees its
/// descriptor even while handles to it are alive (or a cancelled task never drops them).
pub struct Owned<T>(UnsafeCell<Option<T>>);

pub type OwnedSock = Owned<Socket>;

impl<T> Owned<T> {
    pub fn new(sock: T) -> Owned<T> {
        Owned(UnsafeCell::new(Some(sock)))
    }

    /// Closes the descriptor. The caller guarantees nothing is using it.
    pub fn release(&self) {
        // SAFETY: tasks share one thread and no reference to the socket outlives an operation;
        // owners release only with no operation parked and refuse new ones.
        drop(unsafe { (*self.0.get()).take() });
    }

    /// The socket, if it was not released.
    pub fn into_inner(self) -> Option<T> {
        self.0.into_inner()
    }
}

impl<T> Deref for Owned<T> {
    type Target = T;

    fn deref(&self) -> &T {
        // SAFETY: see `release`.
        unsafe { (*self.0.get()).as_ref() }.expect("socket used after it was released")
    }
}

/// Runs `body`, which may park on a socket, counted in `busy`. A cancellation that leaves it
/// still counts it out, and `idle` runs when the count reaches zero, so the close of an
/// enclosing scope can free the descriptor.
fn parked<T>(busy: &Cell<u32>, idle: &dyn Fn(), body: impl FnOnce() -> T) -> T {
    busy.set(busy.get() + 1);
    let leave = || {
        busy.set(busy.get() - 1);
        if busy.get() == 0 {
            idle();
        }
    };
    let r = with_cleanup(&mut { leave }, body);
    leave();
    r
}

/// An unencrypted socket.
pub struct Plain {
    sock: OwnedSock,
    /// Open descriptors over this socket, counting duplicates: a shutdown would stop them all, so
    /// only the last one shuts the socket down.
    open: Rc<Cell<u32>>,
}

impl Plain {
    pub fn new(sock: Socket) -> Plain {
        Plain {
            sock: OwnedSock::new(sock),
            open: Rc::new(Cell::new(1)),
        }
    }

    pub fn socket(&self) -> &Socket {
        &self.sock
    }
}

fn would_block(e: &io::Error) -> bool {
    e.kind() == io::ErrorKind::WouldBlock
}

impl Io for Plain {
    fn fd(&self) -> Borrowed<'_> {
        self.sock.as_sock()
    }

    /// Linux's TCP receive copies until the buffer is full or the queue is empty, and
    /// edge-triggered epoll raises a new edge for any later arrival.
    fn short_read_drains(&self) -> bool {
        cfg!(target_os = "linux")
    }

    fn read(&self, buf: &mut [u8]) -> Step {
        loop {
            return match (&*self.sock).read(buf) {
                Ok(0) if !buf.is_empty() => Step::Eof,
                Ok(n) => Step::Done(n),
                Err(e) if would_block(&e) => Step::WantRead,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => Step::Err(e),
            };
        }
    }

    fn write(&self, data: &[u8]) -> Step {
        loop {
            return match (&*self.sock).write(data) {
                Ok(n) => Step::Done(n),
                Err(e) if would_block(&e) => Step::WantWrite,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => Step::Err(e),
            };
        }
    }

    fn shutdown_write(&self) -> Result<(), NetErr> {
        self.sock
            .shutdown(std::net::Shutdown::Write)
            .map_err(|e| io_to_net(&e))
    }

    fn shutdown_both(&self) {
        let open = self.open.get();
        self.open.set(open - 1);
        if open == 1 {
            let _ = self.sock.shutdown(std::net::Shutdown::Both);
        }
    }

    fn release(&self) {
        self.sock.release();
    }

    fn try_clone(&self) -> Option<io::Result<Box<dyn Io>>> {
        let sock = match self.sock.try_clone() {
            Ok(s) => OwnedSock::new(s),
            Err(e) => return Some(Err(e)),
        };
        self.open.set(self.open.get() + 1);
        Some(Ok(Box::new(Plain {
            sock,
            open: self.open.clone(),
        })))
    }
}

/// Maps an I/O error of a half-close to a network error.
fn io_to_net(e: &io::Error) -> NetErr {
    match e.kind() {
        io::ErrorKind::PermissionDenied => NetErr::PermissionDenied,
        io::ErrorKind::TimedOut => NetErr::Timeout,
        _ => NetErr::Failed(describe_io_error(e)),
    }
}

/// Text of a socket address: `host:port` (IPv6 hosts in brackets) or a path.
pub fn socket_addr_text(addr: &socket2::SockAddr) -> String {
    if let Some(a) = addr.as_socket() {
        return a.to_string();
    }
    #[cfg(unix)]
    if let Some(p) = addr.as_pathname() {
        return p.display().to_string();
    }
    String::new()
}

const READ_CHUNK: i64 = 65536;

/// Drives `io` until `op` makes progress or the deadline passes.
fn drive<T>(
    io: &dyn Io,
    deadline: Deadline,
    mut op: impl FnMut() -> Step,
    done: impl Fn(usize) -> T,
    eof: impl Fn() -> T,
) -> Result<T, DriveError> {
    loop {
        match op() {
            Step::Done(n) => return Ok(done(n)),
            Step::Eof => return Ok(eof()),
            Step::Err(e) => return Err(DriveError::Io(e)),
            Step::WantRead => {
                if wait_fd(io.fd(), Interest::Read, deadline) == Wait::TimedOut {
                    return Err(DriveError::Timeout);
                }
            }
            Step::WantWrite => {
                if wait_fd(io.fd(), Interest::Write, deadline) == Wait::TimedOut {
                    return Err(DriveError::Timeout);
                }
            }
        }
    }
}

pub enum DriveError {
    Timeout,
    Io(io::Error),
}

/// A stream shared with its previous owner (a hijacked server connection).
pub struct SharedIo(pub Rc<dyn Io>);

impl Io for SharedIo {
    fn fd(&self) -> Borrowed<'_> {
        self.0.fd()
    }
    fn read(&self, buf: &mut [u8]) -> Step {
        self.0.read(buf)
    }
    fn write(&self, data: &[u8]) -> Step {
        self.0.write(data)
    }
    fn flush(&self) -> Step {
        self.0.flush()
    }
    fn shutdown_write(&self) -> Result<(), NetErr> {
        self.0.shutdown_write()
    }
    fn shutdown_both(&self) {
        self.0.shutdown_both();
    }
    fn tls_details(&self) -> Option<TlsDetails> {
        self.0.tls_details()
    }
}

/// A connected stream socket.
pub struct Connection {
    owner: Rc<Network>,
    io: Box<dyn Io>,
    closed: Cell<bool>,
    /// Operations parked on `io`; the descriptor is released once a closed connection has none.
    busy: Cell<u32>,
    local: String,
    peer: String,
}

impl Resource for Connection {
    fn close_resource(&self) {
        self.close();
    }
}

impl Connection {
    pub fn new(owner: Rc<Network>, io: Box<dyn Io>, local: String, peer: String) -> Connection {
        Connection {
            owner,
            io,
            closed: Cell::new(false),
            busy: Cell::new(0),
            local,
            peer,
        }
    }

    pub fn owner(&self) -> &Rc<Network> {
        &self.owner
    }

    pub fn local_address(&self) -> &str {
        &self.local
    }

    pub fn peer_address(&self) -> &str {
        &self.peer
    }

    pub fn is_closed(&self) -> bool {
        self.closed.get()
    }

    /// Closes the socket; later reads and writes report `Closed`. Idempotent. The descriptor is
    /// freed now, or when the last parked operation leaves.
    pub fn close(&self) {
        if !self.closed.replace(true) {
            self.io.shutdown_both();
            self.release_if_idle();
        }
    }

    /// A second connection over a duplicate of the socket, closed on its own: one task can read
    /// while another writes. A TLS connection keeps session state a duplicate cannot share.
    pub fn duplicate(&self) -> Result<Rc<Connection>, NetErr> {
        if self.closed.get() {
            return Err(NetErr::Closed);
        }
        let io = self
            .io
            .try_clone()
            .ok_or(NetErr::Unsupported)?
            .map_err(|e| io_to_net(&e))?;
        self.owner
            .adopt_io(io, self.local.clone(), self.peer.clone())
    }

    fn release_if_idle(&self) {
        if self.closed.get() && self.busy.get() == 0 {
            self.io.release();
        }
    }

    fn parked<T>(&self, body: impl FnOnce() -> T) -> T {
        parked(&self.busy, &|| self.release_if_idle(), body)
    }

    fn failure(&self, e: DriveError) -> IoErr {
        match e {
            DriveError::Timeout => IoErr::failed("operation timed out"),
            DriveError::Io(e) => {
                if self.closed.get() {
                    IoErr::Closed
                } else {
                    IoErr::Failed(describe_io_error(&e))
                }
            }
        }
    }

    /// Reads up to `max_bytes` (default and cap 65536); `None` at end of stream.
    pub fn read(
        &self,
        max_bytes: Option<i64>,
        timeout: Option<i64>,
    ) -> Result<Option<Vec<u8>>, IoErr> {
        let max = limit(max_bytes).map_err(|_| IoErr::InvalidInput)?;
        let deadline = Deadline::from_nanos(timeout).map_err(|_| IoErr::InvalidInput)?;
        if self.closed.get() {
            return Err(IoErr::Closed);
        }
        let max = if max_bytes.is_none() {
            READ_CHUNK as u128
        } else {
            max
        };
        if max == 0 {
            return Err(IoErr::InvalidInput);
        }
        let n = max.min(READ_CHUNK as u128) as usize;
        let mut buf = vec![0u8; n];
        match self.read_into(&mut buf, deadline)? {
            0 => Ok(None),
            count => {
                buf.truncate(count);
                Ok(Some(buf))
            }
        }
    }

    /// Reads into `buf` (nonempty); `0` is end of stream.
    pub fn read_into(&self, buf: &mut [u8], deadline: Deadline) -> Result<usize, IoErr> {
        if self.closed.get() {
            return Err(IoErr::Closed);
        }
        let r = self.parked(|| drive(&*self.io, deadline, || self.io.read(buf), |n| n, || 0));
        match r {
            Ok(count) => Ok(count),
            Err(e) => {
                rt::check_cancel();
                Err(self.failure(e))
            }
        }
    }

    /// Writes what the socket takes without waiting; the count accepted. For a task that must
    /// not park on the descriptor because another task already waits on it.
    pub fn write_nowait(&self, data: &[u8]) -> Result<usize, IoErr> {
        if self.closed.get() {
            return Err(IoErr::Closed);
        }
        let mut done = 0;
        while done < data.len() {
            match self.io.write(&data[done..]) {
                Step::Done(n) if n > 0 => done += n,
                Step::Err(e) => return Err(self.failure(DriveError::Io(e))),
                _ => break,
            }
        }
        // TLS buffers records; push out what the socket takes.
        if let Step::Err(e) = self.io.flush() {
            return Err(self.failure(DriveError::Io(e)));
        }
        Ok(done)
    }

    /// Whether an idle connection can no longer carry a new exchange: the peer
    /// closed it, sent unexpected bytes, or it was closed here.
    pub fn is_stale(&self) -> bool {
        if self.closed.get() {
            return true;
        }
        let mut probe = [0u8; 1];
        !matches!(self.io.read(&mut probe), Step::WantRead)
    }

    /// Writes all of `data`; a failure can leave a prefix written.
    pub fn write(&self, data: &[u8], timeout: Option<i64>) -> Result<(), IoErr> {
        let deadline = Deadline::from_nanos(timeout).map_err(|_| IoErr::InvalidInput)?;
        self.write_until(data, deadline)
    }

    /// Like [`Connection::write`] with an absolute deadline.
    pub fn write_until(&self, data: &[u8], deadline: Deadline) -> Result<(), IoErr> {
        if self.closed.get() {
            return Err(IoErr::Closed);
        }
        let mut rest = data;
        while !rest.is_empty() {
            rt::check_cancel();
            let r = self.parked(|| drive(&*self.io, deadline, || self.io.write(rest), |n| n, || 0));
            match r {
                Ok(0) => return Err(IoErr::failed("short write")),
                Ok(n) => rest = &rest[n..],
                Err(e) => return Err(self.failure(e)),
            }
            if self.closed.get() {
                return Err(IoErr::Closed);
            }
        }
        // TLS buffers records; push them out.
        let r = self.parked(|| drive(&*self.io, deadline, || self.io.flush(), |n| n, || 0));
        match r {
            Ok(_) => Ok(()),
            Err(e) => Err(self.failure(e)),
        }
    }

    /// Half-closes the connection.
    pub fn shutdown_write(&self) -> Result<(), NetErr> {
        if self.closed.get() {
            return Err(NetErr::Closed);
        }
        self.io.shutdown_write()
    }

    pub fn tls_info(&self) -> Result<TlsDetails, TlsErr> {
        self.io.tls_details().ok_or(TlsErr::InvalidInput)
    }
}

/// Turns a connected socket into a stream (plain or TLS).
pub type Wrap = Box<dyn FnOnce(Socket) -> Result<Box<dyn Io>, NetErr>>;

/// How a listener turns accepted sockets into connections.
pub type Upgrade = Box<dyn Fn(Socket, Deadline) -> Result<Box<dyn Io>, NetErr>>;

/// A listening socket.
pub struct Listener {
    owner: Rc<Network>,
    sock: OwnedSock,
    closed: Cell<bool>,
    /// Accepts parked on `sock`; see `Connection::busy`.
    busy: Cell<u32>,
    address: String,
    unix_path: Option<String>,
    upgrade: Option<Upgrade>,
    handshake: Deadline,
    handshake_timeout: Option<i64>,
}

impl Resource for Listener {
    fn close_resource(&self) {
        self.close();
    }
}

impl Listener {
    pub fn new(
        owner: Rc<Network>,
        sock: Socket,
        unix_path: Option<String>,
        upgrade: Option<Upgrade>,
        handshake_timeout: Option<i64>,
    ) -> Listener {
        let address = sock
            .local_addr()
            .map(|a| socket_addr_text(&a))
            .unwrap_or_default();
        let address = if address.is_empty() {
            unix_path.clone().unwrap_or_default()
        } else {
            address
        };
        Listener {
            owner,
            sock: OwnedSock::new(sock),
            closed: Cell::new(false),
            busy: Cell::new(0),
            address,
            unix_path,
            upgrade,
            handshake: Deadline::none(),
            handshake_timeout,
        }
    }

    pub fn address(&self) -> &str {
        &self.address
    }

    pub fn is_closed(&self) -> bool {
        self.closed.get()
    }

    pub fn close(&self) {
        if self.closed.replace(true) {
            return;
        }
        let _ = self.sock.shutdown(std::net::Shutdown::Both);
        if let Some(p) = &self.unix_path {
            let _ = std::fs::remove_file(p);
        }
        self.release_if_idle();
    }

    fn release_if_idle(&self) {
        if self.closed.get() && self.busy.get() == 0 {
            self.sock.release();
        }
    }

    fn parked_wait(&self, deadline: Deadline) -> Wait {
        parked(&self.busy, &|| self.release_if_idle(), || {
            wait_fd(self.sock.as_sock(), Interest::Read, deadline)
        })
    }

    pub fn raw(&self) -> &Socket {
        &self.sock
    }

    /// Waits for the next incoming socket; a timeout leaves the listener usable.
    fn accept_socket(&self, deadline: Deadline) -> Result<(Socket, socket2::SockAddr), NetErr> {
        loop {
            rt::check_cancel();
            if self.closed.get() {
                return Err(NetErr::Closed);
            }
            match self.sock.accept() {
                Ok((sock, peer)) => {
                    if self.closed.get() {
                        return Err(NetErr::Closed);
                    }
                    sock.set_nonblocking(true)
                        .map_err(|e| self.owner.io_failure(&e))?;
                    let _ = sock.set_tcp_nodelay(true);
                    return Ok((sock, peer));
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                    if self.parked_wait(deadline) == Wait::TimedOut {
                        rt::check_cancel();
                        return Err(if self.closed.get() {
                            NetErr::Closed
                        } else {
                            NetErr::Timeout
                        });
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                Err(e) => {
                    rt::check_cancel();
                    return Err(if self.closed.get() {
                        NetErr::Closed
                    } else {
                        NetErr::Failed(describe_io_error(&e))
                    });
                }
            }
        }
    }

    /// Accepts one connection; a timeout leaves the listener usable.
    pub fn accept(self: &Rc<Self>, timeout: Option<i64>) -> Result<Rc<Connection>, NetErr> {
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        let _ = (&self.handshake, self.handshake_timeout);
        let (sock, peer) = self.accept_socket(deadline)?;
        let local = sock
            .local_addr()
            .map(|a| socket_addr_text(&a))
            .unwrap_or_default();
        let local = if local.is_empty() {
            self.address.clone()
        } else {
            local
        };
        let mut peer_text = socket_addr_text(&peer);
        if peer_text.is_empty() {
            peer_text = sock
                .peer_addr()
                .map(|a| socket_addr_text(&a))
                .unwrap_or_default();
        }
        let io: Box<dyn Io> = match &self.upgrade {
            None => Box::new(Plain::new(sock)),
            Some(up) => {
                let hs = match self.handshake_timeout {
                    Some(ns) if ns >= 0 => {
                        Deadline::after(std::time::Duration::from_nanos(ns as u64))
                    }
                    _ => Deadline::none(),
                };
                up(sock, earlier(hs, deadline))?
            }
        };
        let conn = Rc::new(Connection::new(self.owner.clone(), io, local, peer_text));
        let as_resource: Rc<dyn Resource> = conn.clone();
        if !self.owner.own(&as_resource) {
            conn.close();
            return Err(NetErr::Closed);
        }
        Ok(conn)
    }

    /// Accepts one TCP connection without wrapping it and returns its operating-system handle
    /// (a descriptor, or a `SOCKET` on Windows) for `Server::adopt`, possibly on another thread.
    /// The caller owns the handle until `Server::adopt` takes it: dropping it unadopted leaks the socket. A listener that
    /// upgrades accepted sockets (TLS) refuses, since the handshake belongs to the adopter.
    /// Identifies this listener as the owner of the handles it released.
    pub fn owner_key(&self) -> usize {
        self as *const Listener as usize
    }

    pub fn accept_raw(&self, timeout: Option<i64>) -> Result<i64, NetErr> {
        if self.upgrade.is_some() {
            return Err(NetErr::InvalidInput);
        }
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        let (sock, _peer) = self.accept_socket(deadline)?;
        Ok(into_raw_handle(sock, self.owner_key()))
    }
}

/// Handles `accept_raw` released and `take_raw_handle` has not yet claimed, so a number a program
/// invents, or a handle used twice, never reaches `from_raw_*`.
static OUTSTANDING: std::sync::LazyLock<std::sync::Mutex<std::collections::HashMap<i64, usize>>> =
    std::sync::LazyLock::new(Default::default);

fn outstanding() -> std::sync::MutexGuard<'static, std::collections::HashMap<i64, usize>> {
    OUTSTANDING.lock().unwrap_or_else(|e| e.into_inner())
}

/// The socket's operating-system handle, released from its owner and recorded as outstanding.
fn into_raw_handle(sock: Socket, owner: usize) -> i64 {
    #[cfg(unix)]
    let raw = {
        use std::os::fd::IntoRawFd;
        i64::from(sock.into_raw_fd())
    };
    #[cfg(windows)]
    let raw = {
        use std::os::windows::io::IntoRawSocket;
        sock.into_raw_socket() as i64
    };
    outstanding().insert(raw, owner);
    raw
}

/// The socket behind a handle `accept_raw` returned, or `None` for a number that is not an
/// outstanding handle (invented, or already adopted).
pub fn take_raw_handle(raw: i64) -> Option<Socket> {
    if outstanding().remove(&raw).is_none() {
        return None;
    }
    #[cfg(unix)]
    {
        use std::os::fd::FromRawFd;
        // SAFETY: `into_raw_handle` released this descriptor from its owner and, having just
        // been removed from the outstanding set, it is claimed once.
        Some(unsafe { Socket::from_raw_fd(raw as i32) })
    }
    #[cfg(windows)]
    {
        use std::os::windows::io::FromRawSocket;
        // SAFETY: as above, for the `SOCKET`.
        Some(unsafe { Socket::from_raw_socket(raw as u64) })
    }
}

fn earlier(a: Deadline, b: Deadline) -> Deadline {
    match (a.remaining(), b.remaining()) {
        (None, _) => b,
        (_, None) => a,
        (Some(x), Some(y)) => {
            if x <= y {
                a
            } else {
                b
            }
        }
    }
}

/// A received datagram.
#[derive(Debug, PartialEq, Eq)]
pub struct Datagram {
    pub data: Vec<u8>,
    pub sender: String,
}

/// A connectionless socket.
pub struct Datagrams {
    owner: Rc<Network>,
    sock: Owned<UdpSocket>,
    closed: Cell<bool>,
    /// Calls parked on `sock`; see `Connection::busy`.
    busy: Cell<u32>,
    address: String,
    /// Taken out for a receive, which can park; see ABI.md.
    scratch: Cell<Vec<u8>>,
}

impl Resource for Datagrams {
    fn close_resource(&self) {
        self.close();
    }
}

impl Datagrams {
    pub fn new(owner: Rc<Network>, sock: UdpSocket) -> Datagrams {
        let address = sock.local_addr().map(|a| a.to_string()).unwrap_or_default();
        Datagrams {
            owner,
            sock: Owned::new(sock),
            closed: Cell::new(false),
            busy: Cell::new(0),
            address,
            scratch: Cell::new(Vec::new()),
        }
    }

    pub fn address(&self) -> &str {
        &self.address
    }

    pub fn close(&self) {
        // `shutdown` is not defined for UDP, so a parked call is not woken: the descriptor is
        // freed now, or when the last parked call returns.
        self.closed.set(true);
        self.release_if_idle();
    }

    fn release_if_idle(&self) {
        if self.closed.get() && self.busy.get() == 0 {
            self.sock.release();
        }
    }

    fn parked_wait(&self, interest: Interest, deadline: Deadline) -> Wait {
        parked(&self.busy, &|| self.release_if_idle(), || {
            wait_fd(self.sock.as_sock(), interest, deadline)
        })
    }

    /// Waits for one datagram. A datagram longer than `max_bytes` is discarded with `LimitExceeded`.
    pub fn receive(
        &self,
        max_bytes: Option<i64>,
        timeout: Option<i64>,
    ) -> Result<Datagram, NetErr> {
        let max = match max_bytes {
            None => 65535,
            Some(n) if n < 0 => return Err(NetErr::InvalidInput),
            Some(n) => n,
        };
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        if self.closed.get() {
            return Err(NetErr::Closed);
        }
        if max <= 0 || max > 65535 {
            return Err(NetErr::InvalidInput);
        }
        let max = max as usize;
        let mut buf = self.scratch.take();
        buf.resize(max + 1, 0);
        let got = self.receive_into(&mut buf, max, deadline);
        self.scratch.set(buf);
        got
    }

    fn receive_into(
        &self,
        buf: &mut [u8],
        max: usize,
        deadline: Deadline,
    ) -> Result<Datagram, NetErr> {
        loop {
            rt::check_cancel();
            match self.sock.recv_from(buf) {
                Ok((n, from)) => {
                    if n > max {
                        return Err(NetErr::LimitExceeded);
                    }
                    return Ok(Datagram {
                        data: buf[..n].to_vec(),
                        sender: from.to_string(),
                    });
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                    if self.parked_wait(Interest::Read, deadline) == Wait::TimedOut {
                        return Err(NetErr::Timeout);
                    }
                    if self.closed.get() {
                        return Err(NetErr::Closed);
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                // Windows refuses a datagram longer than the buffer instead of truncating it
                // (`WSAEMSGSIZE`); the datagram is discarded either way.
                Err(e) if cfg!(windows) && e.raw_os_error() == Some(10040) => {
                    return Err(NetErr::LimitExceeded);
                }
                Err(e) => {
                    return Err(if self.closed.get() {
                        NetErr::Closed
                    } else {
                        NetErr::Failed(describe_io_error(&e))
                    });
                }
            }
        }
    }

    /// Sends `data` as one datagram to `address`.
    pub fn send(&self, data: &[u8], address: &str, timeout: Option<i64>) -> Result<(), NetErr> {
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        if self.closed.get() {
            return Err(NetErr::Closed);
        }
        let target: SocketAddr = match self.owner.resolve_udp_target(address, deadline) {
            Ok(t) => t,
            Err(e) => {
                if self.closed.get() || self.owner.is_closed() {
                    return Err(NetErr::Closed);
                }
                return Err(match e.kind() {
                    io::ErrorKind::TimedOut => NetErr::Timeout,
                    io::ErrorKind::PermissionDenied => NetErr::PermissionDenied,
                    _ => NetErr::Failed(describe_io_error(&e)),
                });
            }
        };
        loop {
            rt::check_cancel();
            match self.sock.send_to(data, target) {
                Ok(n) if n == data.len() => return Ok(()),
                Ok(_) => return Err(NetErr::failed("partial datagram")),
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                    if self.parked_wait(Interest::Write, deadline) == Wait::TimedOut {
                        return Err(NetErr::Timeout);
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                Err(e) => return Err(NetErr::Failed(describe_io_error(&e))),
            }
        }
    }
}

impl Network {
    /// Opens a TCP connection.
    pub fn connect(
        self: &Rc<Self>,
        address: &str,
        timeout: Option<i64>,
    ) -> Result<Rc<Connection>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        let sock = self.dial_tcp(address, deadline)?;
        self.adopt(
            sock,
            Box::new(|s: Socket| Ok(Box::new(Plain::new(s)) as Box<dyn Io>)),
        )
    }

    /// Opens a TCP connection, with a TLS handshake against `server_name` when
    /// `tls` carries a prepared client configuration.
    pub fn dial_stream(
        self: &Rc<Self>,
        address: &str,
        tls: Option<(&Arc<rustls::ClientConfig>, &str)>,
        deadline: Deadline,
    ) -> Result<Rc<Connection>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        let sock = self.dial_tcp(address, deadline)?;
        let wrap: Wrap = match tls {
            None => Box::new(|s: Socket| Ok(Box::new(Plain::new(s)) as Box<dyn Io>)),
            Some((config, name)) => {
                let (config, name) = (config.clone(), name.to_string());
                Box::new(move |s: Socket| tls::connect(s, config, &name, deadline))
            }
        };
        self.adopt(sock, wrap)
    }

    /// Opens a Unix domain socket connection.
    pub fn connect_unix(
        self: &Rc<Self>,
        path: &str,
        timeout: Option<i64>,
    ) -> Result<Rc<Connection>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        let sock = self.dial_unix(path, deadline)?;
        self.adopt(
            sock,
            Box::new(|s: Socket| Ok(Box::new(Plain::new(s)) as Box<dyn Io>)),
        )
    }

    /// Wraps a connected socket in a connection owned by this network.
    pub fn adopt(self: &Rc<Self>, sock: Socket, wrap: Wrap) -> Result<Rc<Connection>, NetErr> {
        let local = sock
            .local_addr()
            .map(|a| socket_addr_text(&a))
            .unwrap_or_default();
        let peer = sock
            .peer_addr()
            .map(|a| socket_addr_text(&a))
            .unwrap_or_default();
        let io = wrap(sock)?;
        self.adopt_io(io, local, peer)
    }

    /// Registers an established stream as a connection of this network.
    pub fn adopt_io(
        self: &Rc<Self>,
        io: Box<dyn Io>,
        local: String,
        peer: String,
    ) -> Result<Rc<Connection>, NetErr> {
        let conn = Rc::new(Connection::new(self.clone(), io, local, peer));
        let as_resource: Rc<dyn Resource> = conn.clone();
        if !self.own(&as_resource) {
            conn.close();
            return Err(NetErr::Closed);
        }
        Ok(conn)
    }

    /// Listens for TCP connections.
    pub fn listen(self: &Rc<Self>, address: &str) -> Result<Rc<Listener>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        if !self.listen_allowed(address) {
            return Err(NetErr::PermissionDenied);
        }
        let sock = self.listen_tcp(address)?;
        self.register_listener(Listener::new(self.clone(), sock, None, None, None))
    }

    /// Connects over TCP and verifies the server against the system roots.
    pub fn connect_tls(
        self: &Rc<Self>,
        address: &str,
        server_name: &str,
        timeout: Option<i64>,
    ) -> Result<Rc<Connection>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        if server_name.is_empty() {
            return Err(NetErr::InvalidInput);
        }
        let options = TlsOptions {
            server_name: server_name.to_string(),
            ..TlsOptions::default()
        };
        self.connect_tls_config(address, &options, timeout)
    }

    /// Connects over TCP and completes a TLS handshake with `options`.
    pub fn connect_tls_config(
        self: &Rc<Self>,
        address: &str,
        options: &TlsOptions,
        timeout: Option<i64>,
    ) -> Result<Rc<Connection>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        let sock = self.dial_tcp(address, deadline)?;
        let config = tls::client_config(options, true)?;
        let name = options.server_name.clone();
        self.adopt(
            sock,
            Box::new(move |s: Socket| tls::connect(s, config, &name, deadline)),
        )
    }

    /// Listens for TCP connections and handshakes each accepted one.
    pub fn listen_tls(
        self: &Rc<Self>,
        address: &str,
        options: &TlsOptions,
        handshake_timeout: Option<i64>,
    ) -> Result<Rc<Listener>, NetErr> {
        if matches!(handshake_timeout, Some(t) if t < 0) {
            return Err(NetErr::InvalidInput);
        }
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        if !self.listen_allowed(address) {
            return Err(NetErr::PermissionDenied);
        }
        let sock = self.listen_tcp(address)?;
        let config = tls::stream_server_config(options)?;
        let clients = !options.roots_pem.is_empty() || options.require_client_certificate;
        let upgrade: Upgrade =
            Box::new(move |s, deadline| tls::accept(s, config.clone(), deadline, clients));
        self.register_listener(Listener::new(
            self.clone(),
            sock,
            None,
            Some(upgrade),
            handshake_timeout,
        ))
    }

    /// Listens on a Unix domain socket.
    pub fn listen_unix_socket(self: &Rc<Self>, path: &str) -> Result<Rc<Listener>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        if self.policy.is_some() {
            return Err(NetErr::PermissionDenied);
        }
        let sock = self.listen_unix(path)?;
        self.register_listener(Listener::new(
            self.clone(),
            sock,
            Some(path.to_string()),
            None,
            None,
        ))
    }

    pub fn register_listener(self: &Rc<Self>, listener: Listener) -> Result<Rc<Listener>, NetErr> {
        let listener = Rc::new(listener);
        let as_resource: Rc<dyn Resource> = listener.clone();
        if !self.own(&as_resource) {
            listener.close();
            return Err(NetErr::Closed);
        }
        Ok(listener)
    }

    /// Binds a datagram socket.
    pub fn bind_datagram(self: &Rc<Self>, address: &str) -> Result<Rc<Datagrams>, NetErr> {
        let sock = self.bind_udp(address)?;
        let d = Rc::new(Datagrams::new(self.clone(), sock));
        let as_resource: Rc<dyn Resource> = d.clone();
        if !self.own(&as_resource) {
            d.close();
            return Err(NetErr::Closed);
        }
        Ok(d)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::net::Network;

    const SEC: Option<i64> = Some(2_000_000_000);

    fn pair(n: &Rc<Network>) -> (Rc<Listener>, Rc<Connection>, Rc<Connection>) {
        let l = n.listen("127.0.0.1:0").unwrap();
        let client = n.connect(l.address(), SEC).unwrap();
        let server = l.accept(SEC).unwrap();
        (l, client, server)
    }

    #[test]
    fn tcp_loopback_half_close_and_eof() {
        let n = Network::new_root();
        let (_l, client, server) = pair(&n);
        client.write(b"hello", SEC).unwrap();
        assert_eq!(server.read(Some(5), SEC).unwrap().unwrap(), b"hello");
        assert_eq!(server.peer_address(), client.local_address());
        client.shutdown_write().unwrap();
        assert_eq!(server.read(Some(5), SEC).unwrap(), None);
        server.write(b"bye", SEC).unwrap();
        assert_eq!(client.read(None, SEC).unwrap().unwrap(), b"bye");
    }

    #[test]
    fn read_validation_and_timeout() {
        let n = Network::new_root();
        let (_l, client, server) = pair(&n);
        assert_eq!(client.read(Some(-1), None), Err(IoErr::InvalidInput));
        assert_eq!(client.read(Some(0), None), Err(IoErr::InvalidInput));
        assert_eq!(client.read(None, Some(-1)), Err(IoErr::InvalidInput));
        assert_eq!(
            client.read(None, Some(30_000_000)),
            Err(IoErr::Failed("operation timed out".into()))
        );
        assert_eq!(client.write(b"x", Some(-1)), Err(IoErr::InvalidInput));
        server.close();
        server.close();
        assert_eq!(server.read(None, None), Err(IoErr::Closed));
        assert_eq!(server.write(b"x", None), Err(IoErr::Closed));
        assert_eq!(server.shutdown_write(), Err(NetErr::Closed));
        assert!(!server.local_address().is_empty());
    }

    #[test]
    fn accept_times_out_and_listener_stays_usable() {
        let n = Network::new_root();
        let l = n.listen("127.0.0.1:0").unwrap();
        assert_eq!(l.accept(Some(20_000_000)).err(), Some(NetErr::Timeout));
        let c = n.connect(l.address(), SEC).unwrap();
        assert!(l.accept(SEC).is_ok());
        drop(c);
        l.close();
        assert_eq!(l.accept(Some(1)).err(), Some(NetErr::Closed));
    }

    #[test]
    fn unix_sockets_round_trip() {
        let dir = std::env::temp_dir().join(format!("ms-net-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("s.sock").display().to_string();
        let n = Network::new_root();
        let l = n.listen_unix_socket(&path).unwrap();
        assert_eq!(l.address(), path);
        let c = n.connect_unix(&path, SEC).unwrap();
        let s = l.accept(SEC).unwrap();
        c.write(b"ping", SEC).unwrap();
        assert_eq!(s.read(None, SEC).unwrap().unwrap(), b"ping");
        c.shutdown_write().unwrap();
        assert_eq!(s.read(None, SEC).unwrap(), None);
        l.close();
        assert!(!std::path::Path::new(&path).exists());
        let restricted = n.restrict(&[], &[], false).unwrap();
        assert_eq!(
            restricted.connect_unix(&path, SEC).err(),
            Some(NetErr::PermissionDenied)
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn restricted_network_denies_and_close_rejects() {
        let n = Network::new_root();
        let r = n.restrict(&[], &[], false).unwrap();
        assert_eq!(
            r.listen("127.0.0.1:0").err(),
            Some(NetErr::PermissionDenied)
        );
        r.close();
        assert_eq!(r.connect("127.0.0.1:1", SEC).err(), Some(NetErr::Closed));
        let ok = n.restrict(&["localhost"], &["127.0.0.0/8"], true).unwrap();
        assert!(ok.listen("127.0.0.1:0").is_ok());
        assert_eq!(
            ok.listen("192.0.2.1:0").err(),
            Some(NetErr::PermissionDenied)
        );
    }

    #[test]
    fn closing_the_network_closes_resources() {
        let n = Network::new_root();
        let (l, client, server) = pair(&n);
        n.close();
        assert!(l.is_closed() && client.is_closed() && server.is_closed());
        assert_eq!(client.read(None, None), Err(IoErr::Closed));
    }

    #[test]
    fn datagrams() {
        let n = Network::new_root();
        let a = n.bind_datagram("127.0.0.1:0").unwrap();
        let b = n.bind_datagram("127.0.0.1:0").unwrap();
        a.send(b"hello", b.address(), None).unwrap();
        let d = b.receive(None, SEC).unwrap();
        assert_eq!(
            (d.data.as_slice(), d.sender.as_str()),
            (&b"hello"[..], a.address())
        );
        a.send(b"", b.address(), None).unwrap();
        assert!(b.receive(None, SEC).unwrap().data.is_empty());
        a.send(b"0123456789", b.address(), None).unwrap();
        assert_eq!(b.receive(Some(4), SEC).err(), Some(NetErr::LimitExceeded));
        assert_eq!(
            b.receive(None, Some(10_000_000)).err(),
            Some(NetErr::Timeout)
        );
        assert_eq!(b.receive(Some(0), None).err(), Some(NetErr::InvalidInput));
        assert_eq!(
            b.receive(Some(65536), None).err(),
            Some(NetErr::InvalidInput)
        );
        b.close();
        b.close();
        assert_eq!(b.receive(None, None).err(), Some(NetErr::Closed));
        assert_eq!(b.send(b"", a.address(), None).err(), Some(NetErr::Closed));
        assert!(!b.address().is_empty());
        let r = n.restrict(&["localhost"], &["127.0.0.0/8"], true).unwrap();
        let rs = r.bind_datagram("127.0.0.1:0").unwrap();
        assert_eq!(
            rs.send(b"", "192.0.2.1:9", None).err(),
            Some(NetErr::PermissionDenied)
        );
        assert_eq!(
            r.bind_datagram("192.0.2.1:0").err(),
            Some(NetErr::PermissionDenied)
        );
    }
}

/// Closes every handle released under `owner` (a `Listener::owner_key`) that no server adopted.
pub fn release_unadopted(owner: usize) {
    let mine: Vec<i64> = outstanding()
        .iter()
        .filter(|(_, held_by)| **held_by == owner)
        .map(|(raw, _)| *raw)
        .collect();
    for raw in mine {
        drop(take_raw_handle(raw));
    }
}
