//! Windows: `SOCKET`s, `WSAPoll`, a loopback datagram socket as the wake-up.

use super::{Ev, Raised, Sockets, mio_interest};
use crate::rt;
use mio::net::TcpStream;
use std::cell::RefCell;
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, UdpSocket};
use std::os::windows::io::{AsRawSocket, AsSocket, BorrowedSocket, FromRawSocket, IntoRawSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use windows_sys::Win32::Foundation::{ERROR_BUFFER_OVERFLOW, NO_ERROR};
use windows_sys::Win32::NetworkManagement::IpHelper::{
    GAA_FLAG_SKIP_ANYCAST, GAA_FLAG_SKIP_FRIENDLY_NAME, GAA_FLAG_SKIP_MULTICAST,
    GAA_FLAG_SKIP_UNICAST, GetAdaptersAddresses, IP_ADAPTER_ADDRESSES_LH,
};
use windows_sys::Win32::NetworkManagement::Ndis::IfOperStatusUp;
use windows_sys::Win32::Networking::WinSock::{
    AF_INET, AF_INET6, AF_UNSPEC, POLLRDNORM, POLLWRNORM, SIO_UDP_CONNRESET, SO_EXCLUSIVEADDRUSE,
    SOCKET_ERROR, SOL_SOCKET, WSAIoctl, WSAPOLLFD, WSAPoll, setsockopt,
};

/// A borrowed socket handle.
pub type Borrowed<'a> = BorrowedSocket<'a>;
/// The handle's raw form, as the runtime takes it: the `SOCKET` as an unsigned 64-bit integer.
pub type Raw = u64;

/// The borrowed handle of a socket-like value.
pub trait AsSock {
    fn as_sock(&self) -> Borrowed<'_>;
}

impl<T: AsSocket + ?Sized> AsSock for T {
    fn as_sock(&self) -> Borrowed<'_> {
        self.as_socket()
    }
}

pub fn raw(sock: Borrowed<'_>) -> Raw {
    sock.as_raw_socket()
}

/// Milliseconds for `WSAPoll`, rounded up so a short wait still waits.
fn millis(d: Duration) -> i32 {
    d.as_micros().div_ceil(1000).min(i32::MAX as u128) as i32
}

fn poll_flags(ev: Ev) -> i16 {
    let mut events = 0;
    if ev.contains(Ev::IN) {
        events |= POLLRDNORM;
    }
    if ev.contains(Ev::OUT) {
        events |= POLLWRNORM;
    }
    events
}

/// `WSAPoll` over `fds`; the count of ready entries, or `None` on failure.
fn wsa_poll(fds: &mut [WSAPOLLFD], timeout_ms: i32) -> Option<usize> {
    // SAFETY: `fds` is a valid, exclusively borrowed array of `fds.len()` entries for the call.
    let n = unsafe { WSAPoll(fds.as_mut_ptr(), fds.len() as u32, timeout_ms) };
    (n != SOCKET_ERROR).then_some(n as usize)
}

/// Waits up to `slice` for one socket; `true` when it is ready, hung up or failed.
pub fn poll_one(sock: Borrowed<'_>, write: bool, slice: Duration) -> bool {
    let mut fds = [WSAPOLLFD {
        fd: raw(sock) as usize,
        events: poll_flags(if write { Ev::OUT } else { Ev::IN }),
        revents: 0,
    }];
    match wsa_poll(&mut fds, millis(slice)) {
        Some(n) => n > 0 && fds[0].revents != 0,
        None => true,
    }
}

/// A handle another thread can signal to make a socket readable: a datagram socket
/// on the loopback interface connected to itself.
pub struct Wake(UdpSocket);

impl Wake {
    pub fn new() -> Option<Wake> {
        let sock = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).ok()?;
        sock.connect(sock.local_addr().ok()?).ok()?;
        sock.set_nonblocking(true).ok()?;
        prepare_udp(&sock).ok()?;
        Some(Wake(sock))
    }

    /// Makes [`Wake::sock`] readable (and keeps it so, until a full buffer).
    pub fn notify(&self) {
        let _ = self.0.send(&[1]);
    }

    pub fn sock(&self) -> Borrowed<'_> {
        self.0.as_socket()
    }

    /// Reads out the pending signals so that [`Wake::sock`] is quiet again.
    pub fn drain(&self) {
        let mut buf = [0u8; 64];
        while self.0.recv(&mut buf).is_ok() {}
    }
}

/// The server's set of watched sockets, on mio (see [`Sockets::report`] for how its edge
/// events serve the server's level-triggered reads and writes).
///
/// mio only watches its own socket types, so each watched socket is lent to a [`TcpStream`]
/// view that never closes it. An IOCP port cannot be waited on by a task, so a helper
/// thread blocks in `mio::Poll::poll`, queues what it sees and signals a [`Wake`] socket
/// the reactor task parks on. The helper never touches the runtime.
pub struct Poller {
    registry: mio::Registry,
    sockets: RefCell<Sockets<Raw>>,
    views: RefCell<HashMap<Raw, TcpStream>>,
    wake: Arc<Wake>,
    shared: Arc<Shared>,
    waker: mio::Waker,
}

struct Shared {
    raised: Mutex<Vec<Raised>>,
    stop: AtomicBool,
}

impl Default for Poller {
    fn default() -> Poller {
        Poller::new()
    }
}

/// Longest the reactor task parks before it looks again (timeouts are swept then).
const PARK_NS: i64 = 50_000_000;
const STOP_TOKEN: mio::Token = mio::Token(usize::MAX);

impl Poller {
    pub fn new() -> Poller {
        let mut poll = mio::Poll::new().expect("poller");
        let registry = poll.registry().try_clone().expect("poller registry");
        let waker = mio::Waker::new(poll.registry(), STOP_TOKEN).expect("poller waker");
        let wake = Arc::new(Wake::new().expect("poller wake socket"));
        let shared = Arc::new(Shared {
            raised: Mutex::new(Vec::new()),
            stop: AtomicBool::new(false),
        });
        let (helper_wake, helper_shared) = (wake.clone(), shared.clone());
        std::thread::Builder::new()
            .name("ms-net-poll".into())
            .spawn(move || {
                let mut events = mio::Events::with_capacity(64);
                while !helper_shared.stop.load(Ordering::Acquire) {
                    if poll.poll(&mut events, None).is_err() {
                        break;
                    }
                    let raised = events
                        .iter()
                        .filter(|e| e.token() != STOP_TOKEN)
                        .map(Raised::from);
                    let mut queue = helper_shared
                        .raised
                        .lock()
                        .unwrap_or_else(|e| e.into_inner());
                    let before = queue.len();
                    queue.extend(raised);
                    let any = queue.len() > before;
                    drop(queue);
                    if any {
                        helper_wake.notify();
                    }
                }
            })
            .expect("poller thread");
        Poller {
            registry,
            sockets: RefCell::new(Sockets::default()),
            views: RefCell::new(HashMap::new()),
            wake,
            shared,
            waker,
        }
    }

    /// Registers `sock` for `ev`, or updates an earlier registration.
    fn arm(&self, sock: Raw, token: u64, ev: Ev) -> std::io::Result<()> {
        let token = mio::Token(token as usize);
        let mut views = self.views.borrow_mut();
        if let Some(view) = views.get_mut(&sock) {
            let r = self.registry.reregister(view, token, mio_interest(ev));
            ms_rt::dbgf!("[arm] {sock} REREGISTER existing view -> {:?}", r.is_ok());
            return r;
        }
        ms_rt::dbgf!("[arm] {sock} register new view");
        // SAFETY: the view never closes the socket: it ends in `into_raw_socket`.
        let stream = unsafe { std::net::TcpStream::from_raw_socket(sock) };
        let mut view = TcpStream::from_std(stream);
        match self.registry.register(&mut view, token, mio_interest(ev)) {
            Ok(()) => {
                views.insert(sock, view);
                Ok(())
            }
            Err(e) => {
                let _ = view.into_raw_socket();
                Err(e)
            }
        }
    }

    pub fn add(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        let sock = raw(sock);
        let armed = self.arm(sock, token, ev).is_ok();
        if armed {
            self.sockets.borrow_mut().set(sock, token, ev);
        }
        armed
    }

    pub fn modify(&self, sock: Borrowed<'_>, token: u64, ev: Ev) {
        let sock = raw(sock);
        if self.arm(sock, token, ev).is_ok() {
            self.sockets.borrow_mut().set(sock, token, ev);
        }
    }

    pub fn delete(&self, sock: Borrowed<'_>) {
        let sock = raw(sock);
        ms_rt::dbgf!("[arm] {sock} delete (had view: {})", self.views.borrow().contains_key(&sock));
        if let Some(mut view) = self.views.borrow_mut().remove(&sock) {
            let _ = self.registry.deregister(&mut view);
            let _ = view.into_raw_socket();
        }
        self.sockets.borrow_mut().remove(sock);
    }

    /// Wakes the parked reactor task.
    pub fn kick(&self) {
        self.wake.notify();
    }

    /// Nothing to forget: interest changes re-arm the registration here.
    pub fn consumed(&self, _sock: Borrowed<'_>, _ev: Ev) {}

    /// Collects up to `max` ready `(token, events)` pairs into `out` without blocking.
    /// Returns how many raised events were read: fewer than `max` means the queue was drained.
    pub fn poll(&self, out: &mut Vec<(u64, Ev)>, max: usize) -> usize {
        out.clear();
        // Empty the wake socket before taking the queue: a signal that lands in between
        // leaves the socket readable for the next park.
        self.wake.drain();
        // Take at most `max`: the rest stay queued for the next call, which the caller makes
        // when this one returns `max`.
        let raised: Vec<Raised> = {
            let mut queue = self.shared.raised.lock().unwrap_or_else(|e| e.into_inner());
            let count = queue.len().min(max);
            queue.drain(..count).collect()
        };
        let count = raised.len();
        self.sockets
            .borrow()
            .report(raised.into_iter(), max, out, |sock, token, ev| {
                let _ = self.arm(sock, token, ev);
            });
        count
    }

    /// Parks the running task until something may be ready (or 50 ms pass); returns
    /// the runtime's ready bits.
    pub fn park(&self, timeout_ns: i64) -> u32 {
        let timeout = if timeout_ns < 0 {
            PARK_NS
        } else {
            timeout_ns.min(PARK_NS)
        };
        rt::wait_fd(self.wake.sock(), 1, timeout)
    }
}

impl Drop for Poller {
    fn drop(&mut self) {
        self.shared.stop.store(true, Ordering::Release);
        let _ = self.waker.wake();
    }
}

/// Whether a failed nonblocking `connect` is merely under way (`WSAEWOULDBLOCK`, which
/// std reports as `WouldBlock`, or `WSAEINPROGRESS`).
pub fn connect_in_progress(e: &std::io::Error) -> bool {
    e.kind() == std::io::ErrorKind::WouldBlock || e.raw_os_error() == Some(10036)
}

/// Options for a listening TCP socket before `bind`. Unlike Unix, `SO_REUSEADDR` here
/// lets another process take over the port, so the port is claimed exclusively.
pub fn prepare_listener(sock: &socket2::Socket) -> std::io::Result<()> {
    let on: i32 = 1;
    // SAFETY: `on` outlives the call and the length is that of the `i32` it points to.
    let rc = unsafe {
        setsockopt(
            sock.as_raw_socket() as usize,
            SOL_SOCKET,
            SO_EXCLUSIVEADDRUSE,
            (&raw const on).cast::<u8>(),
            size_of::<i32>() as i32,
        )
    };
    if rc == SOCKET_ERROR {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

/// Options for a freshly bound datagram socket: an ICMP "port unreachable" must not
/// surface as a connection reset on a later receive.
pub fn prepare_udp(sock: &UdpSocket) -> std::io::Result<()> {
    let off: u32 = 0;
    let mut returned: u32 = 0;
    // SAFETY: the buffers outlive the call; no overlapped I/O or completion routine is used.
    let rc = unsafe {
        WSAIoctl(
            sock.as_raw_socket() as usize,
            SIO_UDP_CONNRESET,
            (&raw const off).cast(),
            size_of::<u32>() as u32,
            std::ptr::null_mut(),
            0,
            &mut returned,
            std::ptr::null_mut(),
            None,
        )
    };
    if rc == SOCKET_ERROR {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

/// DNS servers and the primary DNS suffixes of the operational adapters, in adapter
/// order (the system resolver's own view; there is no `resolv.conf`).
pub fn adapter_dns() -> (Vec<IpAddr>, Vec<String>) {
    let flags = GAA_FLAG_SKIP_UNICAST
        | GAA_FLAG_SKIP_ANYCAST
        | GAA_FLAG_SKIP_MULTICAST
        | GAA_FLAG_SKIP_FRIENDLY_NAME;
    // 16 KiB usually suffices; the call reports the size it needs otherwise.
    let mut len: u32 = 16 * 1024;
    let mut buf: Vec<u64> = Vec::new();
    for _ in 0..4 {
        buf.resize((len as usize).div_ceil(8), 0);
        // SAFETY: `buf` is a writable, 8-byte aligned region of at least `len` bytes.
        let rc = unsafe {
            GetAdaptersAddresses(
                u32::from(AF_UNSPEC),
                flags,
                std::ptr::null(),
                buf.as_mut_ptr().cast::<IP_ADAPTER_ADDRESSES_LH>(),
                &mut len,
            )
        };
        if rc == NO_ERROR {
            // SAFETY: the call succeeded, so `buf` holds a valid adapter list.
            return unsafe { read_adapters(buf.as_ptr().cast()) };
        }
        if rc != ERROR_BUFFER_OVERFLOW {
            break;
        }
    }
    (Vec::new(), Vec::new())
}

/// Reads the DNS servers and suffixes out of an adapter list.
///
/// # Safety
/// `first` must point to the head of a list `GetAdaptersAddresses` filled in, which
/// stays alive for the call.
unsafe fn read_adapters(first: *const IP_ADAPTER_ADDRESSES_LH) -> (Vec<IpAddr>, Vec<String>) {
    let mut servers = Vec::new();
    let mut suffixes = Vec::new();
    let mut adapter = first;
    while !adapter.is_null() {
        // SAFETY: list nodes are valid until the buffer dies (caller's contract).
        let a = unsafe { &*adapter };
        adapter = a.Next;
        if a.OperStatus != IfOperStatusUp {
            continue;
        }
        let mut dns = a.FirstDnsServerAddress;
        while !dns.is_null() {
            // SAFETY: as above.
            let d = unsafe { &*dns };
            dns = d.Next;
            let sa = d.Address.lpSockaddr;
            let len = usize::try_from(d.Address.iSockaddrLength).unwrap_or(0);
            if sa.is_null() || len < 2 {
                continue;
            }
            // SAFETY: the address block holds `len` bytes.
            let bytes = unsafe { std::slice::from_raw_parts(sa.cast::<u8>(), len) };
            let family = u16::from_ne_bytes([bytes[0], bytes[1]]);
            let ip = if family == AF_INET && len >= 8 {
                // sockaddr_in: family, port, address.
                Some(IpAddr::V4(Ipv4Addr::new(
                    bytes[4], bytes[5], bytes[6], bytes[7],
                )))
            } else if family == AF_INET6 && len >= 24 {
                // sockaddr_in6: family, port, flow info, address.
                let mut octets = [0u8; 16];
                octets.copy_from_slice(&bytes[8..24]);
                Some(IpAddr::V6(Ipv6Addr::from(octets)))
            } else {
                None
            };
            // Windows lists the placeholder site-local fec0:0:0:ffff::1-3 for adapters
            // without IPv6 DNS; they never answer.
            if let Some(ip) = ip
                && !is_site_local_placeholder(&ip)
                && !servers.contains(&ip)
            {
                servers.push(ip);
            }
        }
        if !a.DnsSuffix.is_null() {
            // SAFETY: `DnsSuffix` is a NUL-terminated UTF-16 string inside the buffer.
            let suffix = unsafe {
                let mut n = 0;
                while *a.DnsSuffix.add(n) != 0 {
                    n += 1;
                }
                String::from_utf16_lossy(std::slice::from_raw_parts(a.DnsSuffix, n))
            };
            let suffix = suffix.trim_end_matches('.').to_string();
            if !suffix.is_empty() && !suffixes.contains(&suffix) {
                suffixes.push(suffix);
            }
        }
    }
    (servers, suffixes)
}

fn is_site_local_placeholder(ip: &IpAddr) -> bool {
    matches!(ip, IpAddr::V6(v6) if v6.segments()[..4] == [0xfec0, 0, 0, 0xffff])
}
