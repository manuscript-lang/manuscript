//! Windows: `SOCKET`s, `WSAPoll`, a loopback datagram socket as the wake-up.

use super::Ev;
use crate::rt;
use std::cell::RefCell;
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, UdpSocket};
use std::os::windows::io::{AsRawSocket, AsSocket, BorrowedSocket};
use std::time::Duration;
use windows_sys::Win32::Foundation::{ERROR_BUFFER_OVERFLOW, NO_ERROR};
use windows_sys::Win32::NetworkManagement::IpHelper::{
    GAA_FLAG_SKIP_ANYCAST, GAA_FLAG_SKIP_FRIENDLY_NAME, GAA_FLAG_SKIP_MULTICAST,
    GAA_FLAG_SKIP_UNICAST, GetAdaptersAddresses, IP_ADAPTER_ADDRESSES_LH,
};
use windows_sys::Win32::NetworkManagement::Ndis::IfOperStatusUp;
use windows_sys::Win32::Networking::WinSock::{
    AF_INET, AF_INET6, AF_UNSPEC, POLLERR, POLLHUP, POLLNVAL, POLLRDNORM, POLLWRNORM,
    SIO_UDP_CONNRESET, SO_EXCLUSIVEADDRUSE, SOCKET_ERROR, SOL_SOCKET, WSAIoctl, WSAPOLLFD, WSAPoll,
    setsockopt,
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

fn report(revents: i16) -> Ev {
    let mut ev = Ev::NONE;
    if revents & POLLRDNORM != 0 {
        ev = ev | Ev::IN;
    }
    if revents & POLLWRNORM != 0 {
        ev = ev | Ev::OUT;
    }
    if revents & (POLLERR | POLLHUP | POLLNVAL) != 0 {
        ev = ev | Ev::HUP;
    }
    ev
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
}

/// The server's set of watched sockets. Winsock offers no kernel-side set that is
/// itself pollable, so the set lives here and each poll hands it to `WSAPoll`.
pub struct Poller {
    watched: RefCell<HashMap<Raw, (u64, Ev)>>,
    /// Reused buffer for the `WSAPoll` array.
    scratch: RefCell<Vec<WSAPOLLFD>>,
}

/// How long the reactor task sleeps between looks at an idle set.
const IDLE_SLICE_NS: i64 = 2_000_000;

impl Default for Poller {
    fn default() -> Poller {
        Poller::new()
    }
}

impl Poller {
    pub fn new() -> Poller {
        Poller {
            watched: RefCell::new(HashMap::new()),
            scratch: RefCell::new(Vec::new()),
        }
    }

    pub fn add(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        self.watched
            .borrow_mut()
            .insert(raw(sock), (token, ev))
            .is_none()
    }

    pub fn modify(&self, sock: Borrowed<'_>, token: u64, ev: Ev) {
        if let Some(entry) = self.watched.borrow_mut().get_mut(&raw(sock)) {
            *entry = (token, ev);
        }
    }

    pub fn delete(&self, sock: Borrowed<'_>) {
        self.watched.borrow_mut().remove(&raw(sock));
    }

    /// Collects up to `max` ready `(token, events)` pairs into `out` without blocking.
    pub fn poll(&self, out: &mut Vec<(u64, Ev)>, max: usize) {
        out.clear();
        let watched = self.watched.borrow();
        if watched.is_empty() {
            return;
        }
        let mut fds = self.scratch.borrow_mut();
        fds.clear();
        fds.extend(watched.iter().map(|(sock, (_, ev))| WSAPOLLFD {
            fd: *sock as usize,
            events: poll_flags(*ev),
            revents: 0,
        }));
        if wsa_poll(&mut fds, 0).is_none() {
            return;
        }
        out.extend(
            fds.iter()
                .filter(|f| f.revents != 0)
                .filter_map(|f| {
                    let (token, _) = watched.get(&(f.fd as Raw))?;
                    Some((*token, report(f.revents)))
                })
                .take(max),
        );
    }

    /// Parks the running task for a short slice (none when something is already
    /// ready); returns the runtime's ready bits.
    pub fn park(&self) -> u32 {
        let mut ready = Vec::new();
        self.poll(&mut ready, 1);
        rt::sleep(if ready.is_empty() { IDLE_SLICE_NS } else { 0 })
    }
}

/// Whether a failed nonblocking `connect` is merely under way (`WSAEWOULDBLOCK`, which
/// std reports as `WouldBlock`, or `WSAEINPROGRESS`).
pub fn connect_in_progress(e: &std::io::Error) -> bool {
    e.kind() == std::io::ErrorKind::WouldBlock || e.raw_os_error() == Some(10036)
}

/// Options for a listening TCP socket before `bind`. Unlike Unix, `SO_REUSEADDR` here
/// lets another process take over the port, so (like Go) the port is claimed exclusively.
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
/// surface as a connection reset on a later receive (Go clears this too).
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
