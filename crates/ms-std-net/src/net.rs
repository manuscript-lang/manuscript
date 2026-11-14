//! The `Network` service: policy, resolution, ownership of resources and the
//! socket constructors. Connections, listeners and datagram sockets live in
//! [`crate::conn`].

use crate::addr::{parse_port, split_host_port};
use crate::conn::OwnedSock;
use crate::dns::{self, HostConfig, Record};
use crate::error::{NetErr, cannot_resolve, describe_io_error};
use crate::ip::{Cidr, ip_text, normalize};
use crate::policy::{Policy, fold_host, host_ok, ip_ok};
use crate::rt;
use crate::sys::{self, AsSock};
use crate::wait::{Deadline, Interest, Lane, Wait, blocking, try_wait_fd};
use socket2::{Domain, Protocol, SockAddr, Socket, Type};
use std::cell::RefCell;
use std::collections::HashSet;
use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, ToSocketAddrs};
use std::rc::{Rc, Weak as LocalWeak};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, Weak};

/// Something a network owns and closes with itself.
pub trait Resource {
    /// Releases the resource; must be idempotent.
    fn close_resource(&self);
}

/// The record kinds of `DnsKind`, in declaration order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DnsKind {
    A,
    Aaaa,
    Cname,
    Mx,
    Ns,
    Txt,
    Ptr,
    Srv,
}

impl DnsKind {
    pub fn from_index(i: u8) -> Option<DnsKind> {
        Some(match i {
            0 => DnsKind::A,
            1 => DnsKind::Aaaa,
            2 => DnsKind::Cname,
            3 => DnsKind::Mx,
            4 => DnsKind::Ns,
            5 => DnsKind::Txt,
            6 => DnsKind::Ptr,
            7 => DnsKind::Srv,
            _ => return None,
        })
    }

    pub fn index(self) -> u8 {
        self as u8
    }

    pub fn text(self) -> &'static str {
        match self {
            DnsKind::A => "A",
            DnsKind::Aaaa => "AAAA",
            DnsKind::Cname => "CNAME",
            DnsKind::Mx => "MX",
            DnsKind::Ns => "NS",
            DnsKind::Txt => "TXT",
            DnsKind::Ptr => "PTR",
            DnsKind::Srv => "SRV",
        }
    }

    fn qtype(self) -> u16 {
        match self {
            DnsKind::A => dns::TYPE_A,
            DnsKind::Aaaa => dns::TYPE_AAAA,
            DnsKind::Cname => dns::TYPE_CNAME,
            DnsKind::Mx => dns::TYPE_MX,
            DnsKind::Ns => dns::TYPE_NS,
            DnsKind::Txt => dns::TYPE_TXT,
            DnsKind::Ptr => dns::TYPE_PTR,
            DnsKind::Srv => dns::TYPE_SRV,
        }
    }
}

/// One `DnsRecord`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DnsRecord {
    pub kind: DnsKind,
    pub value: String,
    pub priority: i64,
    pub weight: i64,
    pub port: i64,
}

/// The OS-backed network and its derived, restricted children.
///
/// A `Network` is shared between threads (a promise may use one), so its own state is atomic or
/// locked. The resources it opened (`Rc` handles that are bound to their thread) are registered
/// in the registry of the thread that opened them: closing the network closes the ones opened on
/// the closing thread at once; the others see `is_closed` at their next operation.
pub struct Network {
    id: u64,
    pub(crate) policy: Option<Arc<Policy>>,
    resolver: Option<SocketAddr>,
    parent: Option<Weak<Network>>,
    closed: AtomicBool,
    children: Mutex<Vec<Weak<Network>>>,
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

thread_local! {
    /// Resources opened on this thread, by owning network id, oldest first.
    static LOCAL: RefCell<Vec<(u64, LocalWeak<dyn Resource>)>> = const { RefCell::new(Vec::new()) };
}

impl Resource for Network {
    fn close_resource(&self) {
        self.close();
    }
}

impl Network {
    fn make(
        policy: Option<Arc<Policy>>,
        resolver: Option<SocketAddr>,
        parent: Option<Weak<Network>>,
    ) -> Arc<Network> {
        Arc::new(Network {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            policy,
            resolver,
            parent,
            closed: AtomicBool::new(false),
            children: Mutex::new(Vec::new()),
        })
    }

    /// An unrestricted network over the host's sockets and resolver.
    pub fn new_root() -> Arc<Network> {
        Network::make(None, None, None)
    }

    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
    }

    /// Whether this network's policy lets requests name `host`.
    pub fn host_allowed(&self, host: &str) -> bool {
        host_ok(&self.policy, host)
    }

    /// Registers a resource opened on this thread; `false` when the network is already closed.
    pub fn own(&self, r: &Rc<dyn Resource>) -> bool {
        if self.is_closed() {
            return false;
        }
        LOCAL.with(|local| {
            let mut list = local.borrow_mut();
            if list.len() >= 64 && list.len().is_power_of_two() {
                list.retain(|(_, w)| w.strong_count() > 0);
            }
            list.push((self.id, Rc::downgrade(r)));
        });
        true
    }

    fn adopt_child(&self, child: &Arc<Network>) -> bool {
        let mut children = self.children.lock().unwrap_or_else(|e| e.into_inner());
        if self.is_closed() {
            return false;
        }
        children.retain(|w| w.strong_count() > 0);
        children.push(Arc::downgrade(child));
        true
    }

    /// Whether this network is `other` or derived from it.
    pub fn is_within(&self, other: &Network) -> bool {
        if std::ptr::eq(self, other) {
            return true;
        }
        self.parent
            .as_ref()
            .and_then(Weak::upgrade)
            .is_some_and(|p| p.is_within(other))
    }

    /// Closes everything this network opened, innermost first. Idempotent.
    pub fn close(&self) {
        if self.closed.swap(true, Ordering::AcqRel) {
            return;
        }
        let children: Vec<_> =
            std::mem::take(&mut *self.children.lock().unwrap_or_else(|e| e.into_inner()));
        let mine: Vec<_> = LOCAL.with(|local| {
            let mut list = local.borrow_mut();
            let mut taken = Vec::new();
            list.retain(|(id, w)| {
                if *id == self.id {
                    taken.push(w.clone());
                    false
                } else {
                    true
                }
            });
            taken
        });
        for w in mine.iter().rev() {
            if let Some(r) = w.upgrade() {
                r.close_resource();
            }
        }
        for w in children.iter().rev() {
            if let Some(c) = w.upgrade() {
                c.close();
            }
        }
        if let Some(p) = self.parent.as_ref().and_then(Weak::upgrade) {
            p.children
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .retain(|w| {
                    w.upgrade()
                        .is_some_and(|c| !std::ptr::eq(Arc::as_ptr(&c), self))
                });
        }
    }

    /// Maps a host I/O failure to the error a call reports.
    pub fn io_failure(&self, e: &io::Error) -> NetErr {
        if self.is_closed() {
            return NetErr::Closed;
        }
        match e.kind() {
            io::ErrorKind::PermissionDenied => NetErr::PermissionDenied,
            io::ErrorKind::TimedOut => NetErr::Timeout,
            _ => NetErr::Failed(describe_io_error(e)),
        }
    }

    /// A derived network limited to `hosts` and CIDR `cidrs`.
    pub fn restrict(
        self: &Arc<Self>,
        hosts: &[&str],
        cidrs: &[&str],
        allow_listen: bool,
    ) -> Result<Arc<Network>, NetErr> {
        let mut set = HashSet::new();
        for host in hosts {
            if host.is_empty() || host.contains(['/', '\\', '\0', ' ', ':']) {
                return Err(NetErr::InvalidInput);
            }
            set.insert(fold_host(host));
        }
        let mut prefixes = Vec::new();
        for text in cidrs {
            prefixes.push(Cidr::parse(text).map_err(|_| NetErr::InvalidInput)?);
        }
        let policy = Arc::new(Policy::new(
            set,
            prefixes,
            allow_listen && self.policy.as_ref().is_none_or(|p| p.listen),
            self.policy.clone(),
        ));
        let child = Network::make(Some(policy), self.resolver, Some(Arc::downgrade(self)));
        if !self.adopt_child(&child) {
            return Err(NetErr::Closed);
        }
        Ok(child)
    }

    /// A derived network resolving through the DNS server at `address`.
    pub fn with_resolver(self: &Arc<Self>, address: &str) -> Result<Arc<Network>, NetErr> {
        let host_and_port = split_host_port(address);
        let ip = host_and_port.and_then(|(h, _)| h.parse::<IpAddr>().ok());
        let (Some((host, port)), Some(ip)) = (host_and_port, ip) else {
            return Err(NetErr::InvalidInput);
        };
        if !host_ok(&self.policy, host) || !ip_ok(&self.policy, ip) {
            return Err(NetErr::PermissionDenied);
        }
        let port = parse_port(port).ok_or(NetErr::InvalidInput)?;
        let child = Network::make(
            self.policy.clone(),
            Some(SocketAddr::new(ip, port)),
            Some(Arc::downgrade(self)),
        );
        if !self.adopt_child(&child) {
            return Err(NetErr::Closed);
        }
        Ok(child)
    }

    // ---------------------------------------------------------------- resolution

    /// Resolves a host to addresses (literals pass through), within the policy.
    pub fn resolve_ips(&self, host: &str, deadline: Deadline) -> Result<Vec<IpAddr>, NetErr> {
        if let Ok(ip) = host.parse::<IpAddr>() {
            return Ok(vec![ip]);
        }
        if host.is_empty() {
            return Err(NetErr::failed(cannot_resolve(host)));
        }
        let ips = self.lookup_ips(host, deadline, None)?;
        if ips.is_empty() {
            return Err(NetErr::failed(cannot_resolve(host)));
        }
        Ok(ips)
    }

    /// Addresses of `host`, optionally one family only (`Some(true)` for IPv4).
    fn lookup_ips(
        &self,
        host: &str,
        deadline: Deadline,
        v4: Option<bool>,
    ) -> Result<Vec<IpAddr>, NetErr> {
        let keep = |ip: &IpAddr| v4.is_none_or(|want| ip.is_ipv4() == want);
        if let Some(server) = self.resolver {
            let config = HostConfig::load();
            let candidates = config.candidates(host);
            let mut out = Vec::new();
            let mut last = None;
            let kinds: &[u16] = match v4 {
                Some(true) => &[dns::TYPE_A],
                Some(false) => &[dns::TYPE_AAAA],
                None => &[dns::TYPE_A, dns::TYPE_AAAA],
            };
            for qtype in kinds {
                match dns::lookup(&[server], &candidates, *qtype, deadline, host) {
                    Ok(records) => {
                        for r in records {
                            if let Ok(ip) = r.value.parse::<IpAddr>() {
                                out.push(normalize(ip));
                            }
                        }
                    }
                    Err(NetErr::Timeout) => return Err(NetErr::Timeout),
                    Err(e) => last = Some(e),
                }
            }
            if out.is_empty() {
                return Err(last.unwrap_or_else(|| NetErr::failed(cannot_resolve(host))));
            }
            return Ok(out);
        }
        // `localhost` needs no system lookup, so it needs no pool thread either: handing it off
        // cost a task switch and two wake-ups (33 us) for an answer that is a constant.
        if let Some(ips) = localhost_addrs(&host.to_ascii_lowercase()) {
            return Ok(ips.into_iter().map(normalize).filter(keep).collect());
        }
        match blocking(Lane::Dns, host.to_string(), resolve, deadline)? {
            None => Err(NetErr::Timeout),
            Some(Err(_)) => Err(NetErr::failed(cannot_resolve(host))),
            Some(Ok(mut ips)) => {
                let mut seen = HashSet::new();
                ips.retain(|ip| seen.insert(*ip));
                Ok(ips.into_iter().map(normalize).filter(keep).collect())
            }
        }
    }

    /// `Network.lookup`.
    pub fn lookup(
        &self,
        name: &str,
        max_records: Option<i64>,
        timeout: Option<i64>,
    ) -> Result<Vec<String>, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        let max = limit(max_records)?;
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        if !host_ok(&self.policy, name) {
            return Err(NetErr::PermissionDenied);
        }
        let records = if name.parse::<IpAddr>().is_ok() {
            vec![name.to_string()]
        } else {
            let ips = self.lookup_ips(name, deadline, None)?;
            rt::check()?;
            if self.is_closed() {
                return Err(NetErr::Closed);
            }
            if ips.is_empty() {
                return Err(NetErr::failed(cannot_resolve(name)));
            }
            ips.iter().map(ip_text).collect()
        };
        if records.len() as u128 > max {
            return Err(NetErr::LimitExceeded);
        }
        Ok(records)
    }

    /// `Network.resolve`.
    pub fn resolve(
        &self,
        name: &str,
        kind: DnsKind,
        max_records: Option<i64>,
        timeout: Option<i64>,
    ) -> Result<Vec<DnsRecord>, NetErr> {
        let max = limit(max_records)?;
        let deadline = Deadline::from_nanos(timeout).map_err(|_| NetErr::InvalidInput)?;
        if !host_ok(&self.policy, name) {
            return Err(NetErr::PermissionDenied);
        }
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        let plain = |value: String| DnsRecord {
            kind,
            value,
            priority: 0,
            weight: 0,
            port: 0,
        };
        let mut out = Vec::new();
        match kind {
            DnsKind::A | DnsKind::Aaaa => {
                let ips = self.lookup_ips(name, deadline, Some(kind == DnsKind::A))?;
                out.extend(ips.iter().map(|ip| plain(ip_text(ip))));
            }
            _ => {
                let config = HostConfig::load();
                let servers = match self.resolver {
                    Some(s) => vec![s],
                    None => config.servers.clone(),
                };
                let (query_name, candidates) = if kind == DnsKind::Ptr {
                    let ip = name
                        .parse::<IpAddr>()
                        .map_err(|_| NetErr::failed("unrecognized address"))?;
                    let reverse = dns::reverse_name(&ip);
                    (reverse.clone(), vec![reverse])
                } else {
                    (name.to_string(), config.candidates(name))
                };
                let records =
                    dns::lookup(&servers, &candidates, kind.qtype(), deadline, &query_name);
                match records {
                    Ok(records) => out.extend(records.into_iter().map(|r: Record| DnsRecord {
                        kind,
                        value: r.value,
                        priority: r.priority,
                        weight: r.weight,
                        port: r.port,
                    })),
                    Err(e) => {
                        rt::check()?;
                        if self.is_closed() {
                            return Err(NetErr::Closed);
                        }
                        return Err(e);
                    }
                }
            }
        }
        if out.len() as u128 > max {
            return Err(NetErr::LimitExceeded);
        }
        Ok(out)
    }

    // ------------------------------------------------------------------- dialing

    /// Connects to the first reachable permitted address of `address`.
    pub fn dial_tcp(&self, address: &str, deadline: Deadline) -> Result<Socket, NetErr> {
        let (host, port) =
            split_host_port(address).ok_or_else(|| NetErr::failed("missing port in address"))?;
        if !host_ok(&self.policy, host) {
            return Err(NetErr::PermissionDenied);
        }
        let port = parse_port(port).ok_or_else(|| NetErr::failed("invalid port"))?;
        let ips = self.resolve_ips(host, deadline)?;
        let mut last = NetErr::failed("no permitted address");
        for ip in ips {
            if !ip_ok(&self.policy, ip) {
                last = NetErr::PermissionDenied;
                continue;
            }
            match connect_nonblocking(SocketAddr::new(ip, port), deadline) {
                Ok(sock) => return Ok(sock),
                Err(ConnectError::Timeout) => return Err(NetErr::Timeout),
                Err(ConnectError::Cancelled) => return Err(crate::rt::Cancelled.into()),
                Err(ConnectError::Io(e)) => {
                    last = self.io_failure(&e);
                    if self.is_closed() {
                        return Err(last);
                    }
                }
            }
        }
        Err(last)
    }

    /// Connects to a Unix domain socket (unrestricted networks only).
    pub fn dial_unix(&self, path: &str, deadline: Deadline) -> Result<Socket, NetErr> {
        if self.policy.is_some() {
            return Err(NetErr::PermissionDenied);
        }
        if path.is_empty() {
            return Err(NetErr::InvalidInput);
        }
        let sock =
            Socket::new(Domain::UNIX, Type::STREAM, None).map_err(|e| self.io_failure(&e))?;
        sock.set_nonblocking(true)
            .map_err(|e| self.io_failure(&e))?;
        let addr = SockAddr::unix(path).map_err(|e| self.io_failure(&e))?;
        let sock = OwnedSock::new(sock);
        match sock.connect(&addr) {
            Ok(()) => Ok(unwrap_sock(sock)),
            Err(e) if in_progress(&e) => {
                finish_connect(&sock, deadline).map_err(|e| match e {
                    ConnectError::Timeout => NetErr::Timeout,
                    ConnectError::Cancelled => crate::rt::Cancelled.into(),
                    ConnectError::Io(e) => self.io_failure(&e),
                })?;
                Ok(unwrap_sock(sock))
            }
            Err(e) => Err(self.io_failure(&e)),
        }
    }

    /// Whether the policy allows listening on `address`.
    pub fn listen_allowed(&self, address: &str) -> bool {
        let Some(policy) = &self.policy else {
            return true;
        };
        if !policy.listen {
            return false;
        }
        let Some((host, _)) = split_host_port(address) else {
            return false;
        };
        host.parse::<IpAddr>().is_ok_and(|ip| policy.ip(ip))
    }

    /// Binds a listening TCP socket.
    pub fn listen_tcp(&self, address: &str) -> Result<Socket, NetErr> {
        let (host, port) =
            split_host_port(address).ok_or_else(|| NetErr::failed("missing port in address"))?;
        let port = parse_port(port).ok_or_else(|| NetErr::failed("invalid port"))?;
        let ip = if host.is_empty() {
            IpAddr::V6(std::net::Ipv6Addr::UNSPECIFIED)
        } else if let Ok(ip) = host.parse::<IpAddr>() {
            ip
        } else {
            let ips = self.resolve_ips(host, Deadline::none())?;
            ips.iter()
                .find(|ip| ip.is_ipv4())
                .or(ips.first())
                .copied()
                .ok_or_else(|| NetErr::failed(cannot_resolve(host)))?
        };
        let mut addr = SocketAddr::new(ip, port);
        let sock = match Socket::new(Domain::for_address(addr), Type::STREAM, Some(Protocol::TCP)) {
            Ok(sock) => sock,
            // A host without IPv6 serves the empty host on IPv4 alone.
            Err(_) if host.is_empty() => {
                addr = SocketAddr::new(IpAddr::V4(std::net::Ipv4Addr::UNSPECIFIED), port);
                Socket::new(Domain::for_address(addr), Type::STREAM, Some(Protocol::TCP))
                    .map_err(|e| self.io_failure(&e))?
            }
            Err(e) => return Err(self.io_failure(&e)),
        };
        sys::prepare_listener(&sock).map_err(|e| self.io_failure(&e))?;
        if addr.ip().is_unspecified() && addr.is_ipv6() {
            // A wildcard listener serves both families (Windows defaults to v6 only).
            sock.set_only_v6(false).map_err(|e| self.io_failure(&e))?;
        }
        sock.bind(&addr.into()).map_err(|e| self.io_failure(&e))?;
        sock.listen(4096).map_err(|e| self.io_failure(&e))?;
        sock.set_nonblocking(true)
            .map_err(|e| self.io_failure(&e))?;
        Ok(sock)
    }

    /// Binds a listening Unix socket (unrestricted networks only).
    pub fn listen_unix(&self, path: &str) -> Result<Socket, NetErr> {
        if self.policy.is_some() {
            return Err(NetErr::PermissionDenied);
        }
        // An empty path would autobind an abstract address that nothing can connect to.
        if path.is_empty() {
            return Err(NetErr::InvalidInput);
        }
        let sock =
            Socket::new(Domain::UNIX, Type::STREAM, None).map_err(|e| self.io_failure(&e))?;
        let addr = SockAddr::unix(path).map_err(|e| self.io_failure(&e))?;
        sock.bind(&addr).map_err(|e| self.io_failure(&e))?;
        sock.listen(4096).map_err(|e| self.io_failure(&e))?;
        sock.set_nonblocking(true)
            .map_err(|e| self.io_failure(&e))?;
        Ok(sock)
    }

    /// Binds a UDP socket.
    pub fn bind_udp(&self, address: &str) -> Result<std::net::UdpSocket, NetErr> {
        if self.is_closed() {
            return Err(NetErr::Closed);
        }
        if !self.listen_allowed(address) {
            return Err(NetErr::PermissionDenied);
        }
        let (host, port) =
            split_host_port(address).ok_or_else(|| NetErr::failed("missing port in address"))?;
        let port = parse_port(port).ok_or_else(|| NetErr::failed("invalid port"))?;
        let ip = if host.is_empty() {
            IpAddr::V6(std::net::Ipv6Addr::UNSPECIFIED)
        } else {
            let ips = self.resolve_ips(host, Deadline::none())?;
            ips.iter()
                .find(|ip| ip.is_ipv4())
                .or(ips.first())
                .copied()
                .ok_or_else(|| NetErr::failed(cannot_resolve(host)))?
        };
        let bound = bind_udp_socket(SocketAddr::new(ip, port)).or_else(|e| {
            // A host without IPv6 serves the empty host on IPv4 alone.
            if host.is_empty()
                && Socket::new(Domain::IPV6, Type::DGRAM, Some(Protocol::UDP)).is_err()
            {
                bind_udp_socket(SocketAddr::new(
                    IpAddr::V4(std::net::Ipv4Addr::UNSPECIFIED),
                    port,
                ))
            } else {
                Err(e)
            }
        });
        let sock = bound.map_err(|e| NetErr::Failed(describe_io_error(&e)))?;
        sock.set_nonblocking(true)
            .map_err(|e| self.io_failure(&e))?;
        Ok(sock)
    }

    /// Resolves `address` to one permitted socket address (datagram sends).
    pub fn resolve_udp_target(
        &self,
        address: &str,
        deadline: Deadline,
    ) -> Result<SocketAddr, io::Error> {
        let denied = || io::Error::from(io::ErrorKind::PermissionDenied);
        let invalid = |m: &str| io::Error::other(m.to_string());
        let (host, port) =
            split_host_port(address).ok_or_else(|| invalid("missing port in address"))?;
        let port = parse_port(port).ok_or_else(|| invalid("invalid port"))?;
        if !host_ok(&self.policy, host) {
            return Err(denied());
        }
        let ips = self.resolve_ips(host, deadline).map_err(|e| match e {
            NetErr::Timeout => io::Error::from(io::ErrorKind::TimedOut),
            other => io::Error::other(other.message()),
        })?;
        ips.into_iter()
            .find(|ip| ip_ok(&self.policy, *ip))
            .map(|ip| SocketAddr::new(ip, port))
            .ok_or_else(denied)
    }
}

/// The system resolver's addresses for `host`; runs on a pool thread.
///
/// Host names are case-insensitive, but the static musl resolver Linux programs link matches
/// `/etc/hosts` names exactly, so `LOCALHOST` would fail there while it resolves elsewhere.
#[expect(clippy::ptr_arg, reason = "a pool job takes `&I` for its input type")]
fn resolve(host: &String) -> io::Result<Vec<IpAddr>> {
    let name = host.to_ascii_lowercase();
    (name.as_str(), 0u16)
        .to_socket_addrs()
        .map(|it| it.map(|a| a.ip()).collect())
}

/// `localhost` and `*.localhost` always name the loopback interface (RFC 6761), so they need no
/// system lookup and no pool thread (`lookup_ips` answers them directly). Windows runners answered
/// `localhost` too slowly for a two-second deadline.
fn localhost_addrs(name: &str) -> Option<Vec<IpAddr>> {
    let name = name.strip_suffix('.').unwrap_or(name);
    let local = name == "localhost" || name.ends_with(".localhost");
    local.then(|| {
        vec![
            IpAddr::V4(Ipv4Addr::LOCALHOST),
            IpAddr::V6(Ipv6Addr::LOCALHOST),
        ]
    })
}

/// A bound UDP socket; a wildcard IPv6 address serves both families.
fn bind_udp_socket(addr: SocketAddr) -> io::Result<std::net::UdpSocket> {
    let sock = Socket::new(Domain::for_address(addr), Type::DGRAM, Some(Protocol::UDP))?;
    if addr.ip().is_unspecified() && addr.is_ipv6() {
        sock.set_only_v6(false)?;
    }
    sock.bind(&addr.into())?;
    let sock = std::net::UdpSocket::from(sock);
    sys::prepare_udp(&sock)?;
    Ok(sock)
}

/// Validates an optional nonnegative limit; none means unlimited.
pub fn limit(v: Option<i64>) -> Result<u128, NetErr> {
    match v {
        None => Ok(u128::MAX),
        Some(n) if n < 0 => Err(NetErr::InvalidInput),
        Some(n) => Ok(n as u128),
    }
}

pub enum ConnectError {
    Timeout,
    Cancelled,
    Io(io::Error),
}

fn unwrap_sock(sock: OwnedSock) -> Socket {
    sock.into_inner().expect("a socket that was not released")
}

fn in_progress(e: &io::Error) -> bool {
    sys::connect_in_progress(e)
}

fn finish_connect(sock: &Socket, deadline: Deadline) -> Result<(), ConnectError> {
    match try_wait_fd(sock.as_sock(), Interest::Write, deadline) {
        Err(_) => return Err(ConnectError::Cancelled),
        Ok(Wait::TimedOut) => return Err(ConnectError::Timeout),
        Ok(Wait::Ready) => {}
    }
    match sock.take_error() {
        Ok(None) => Ok(()),
        Ok(Some(e)) | Err(e) => Err(ConnectError::Io(e)),
    }
}

/// Starts a nonblocking connect and waits for it within `deadline`.
pub fn connect_nonblocking(addr: SocketAddr, deadline: Deadline) -> Result<Socket, ConnectError> {
    let sock = Socket::new(Domain::for_address(addr), Type::STREAM, Some(Protocol::TCP))
        .map_err(ConnectError::Io)?;
    sock.set_nonblocking(true).map_err(ConnectError::Io)?;
    let _ = sock.set_tcp_nodelay(true);
    let sock = OwnedSock::new(sock);
    match sock.connect(&addr.into()) {
        Ok(()) => Ok(unwrap_sock(sock)),
        Err(e) if in_progress(&e) => {
            finish_connect(&sock, deadline)?;
            Ok(unwrap_sock(sock))
        }
        Err(e) => Err(ConnectError::Io(e)),
    }
}

thread_local! {
    static ROOT: RefCell<Option<Arc<Network>>> = const { RefCell::new(None) };
}

/// The host's root network; repeated calls return the same one.
pub fn root() -> Arc<Network> {
    ROOT.with(|r| r.borrow_mut().get_or_insert_with(Network::new_root).clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn root_is_stable() {
        assert!(Arc::ptr_eq(&root(), &root()));
    }

    #[test]
    fn restrict_validates() {
        let n = Network::new_root();
        assert_eq!(
            n.restrict(&["a b"], &[], false).err(),
            Some(NetErr::InvalidInput)
        );
        assert_eq!(
            n.restrict(&[""], &[], false).err(),
            Some(NetErr::InvalidInput)
        );
        assert_eq!(
            n.restrict(&[], &["nope"], false).err(),
            Some(NetErr::InvalidInput)
        );
        assert!(n.restrict(&["localhost"], &["127.0.0.0/8"], true).is_ok());
    }

    #[test]
    fn child_cannot_restore_parent_listening_permission() {
        let root = Network::new_root();
        let parent = root.restrict(&[], &["127.0.0.0/8"], false).unwrap();
        let child = parent.restrict(&[], &["127.0.0.0/8"], true).unwrap();
        let grandchild = child.restrict(&[], &["127.0.0.0/8"], true).unwrap();
        let resolved = parent.with_resolver("127.0.0.1:53").unwrap();
        let resolved_child = resolved.restrict(&[], &["127.0.0.0/8"], true).unwrap();
        for network in [&parent, &child, &grandchild, &resolved_child] {
            assert!(!network.listen_allowed("127.0.0.1:0"));
            assert!(matches!(
                network.bind_udp("127.0.0.1:0"),
                Err(NetErr::PermissionDenied)
            ));
            assert!(matches!(
                network.listen("127.0.0.1:0"),
                Err(NetErr::PermissionDenied)
            ));
        }
        let allowed = root.restrict(&[], &["127.0.0.0/8"], true).unwrap();
        let narrowed = allowed.restrict(&[], &["127.0.0.0/8"], true).unwrap();
        assert!(narrowed.listen_allowed("127.0.0.1:0"));
        assert!(!narrowed.listen_allowed("192.0.2.1:0"));
    }

    #[test]
    fn localhost_names_resolve_to_loopback_in_any_case() {
        let loopback = vec![
            IpAddr::V4(Ipv4Addr::LOCALHOST),
            IpAddr::V6(Ipv6Addr::LOCALHOST),
        ];
        let network = Network::new_root();
        let deadline = Deadline::from_nanos(None).unwrap();
        for name in ["localhost", "LocalHost", "localhost.", "app.localhost"] {
            // Answered without a pool thread, so no runtime is needed.
            assert_eq!(
                network.resolve_ips(name, deadline).unwrap(),
                loopback,
                "{name}"
            );
        }
        assert_eq!(localhost_addrs("notlocalhost"), None);
        assert_eq!(localhost_addrs("localhost.example"), None);
    }

    #[test]
    fn lookup_literal_and_limits() {
        let n = Network::new_root();
        assert_eq!(
            n.lookup("127.0.0.1", None, None).unwrap(),
            vec!["127.0.0.1"]
        );
        assert_eq!(
            n.lookup("127.0.0.1", Some(0), None),
            Err(NetErr::LimitExceeded)
        );
        assert_eq!(
            n.lookup("127.0.0.1", Some(-1), None),
            Err(NetErr::InvalidInput)
        );
        assert_eq!(
            n.lookup("127.0.0.1", None, Some(-1)),
            Err(NetErr::InvalidInput)
        );
        let r = n.restrict(&[], &[], false).unwrap();
        assert_eq!(
            r.lookup("localhost", None, None),
            Err(NetErr::PermissionDenied)
        );
        let localhost = n.lookup("localhost", None, Some(5_000_000_000)).unwrap();
        assert!(!localhost.is_empty());
        let shouted = n.lookup("LocalHost", None, Some(5_000_000_000)).unwrap();
        assert_eq!(shouted, localhost);
    }

    #[test]
    fn explicit_resolver_answers_every_kind() {
        let server = dns::testing::fake_dns();
        let n = Network::new_root()
            .with_resolver(&server.to_string())
            .unwrap();
        let t = Some(2_000_000_000);
        for kind in [
            DnsKind::A,
            DnsKind::Aaaa,
            DnsKind::Cname,
            DnsKind::Txt,
            DnsKind::Mx,
            DnsKind::Ns,
            DnsKind::Srv,
        ] {
            let r = n.resolve("test.", kind, Some(8), t).unwrap();
            assert!(!r.is_empty(), "{kind:?}");
            assert!(r.iter().all(|x| x.kind == kind));
        }
        let ptr = n.resolve("127.0.0.1", DnsKind::Ptr, Some(8), t).unwrap();
        assert_eq!(ptr[0].value, "host.test.");
        let mx = &n.resolve("test.", DnsKind::Mx, None, None).unwrap()[0];
        assert_eq!(
            (mx.value.as_str(), mx.priority, mx.weight, mx.port),
            ("mail.test.", 10, 0, 0)
        );
        let srv = &n.resolve("test.", DnsKind::Srv, None, None).unwrap()[0];
        assert_eq!(
            (srv.value.as_str(), srv.priority, srv.weight, srv.port),
            ("service.test.", 1, 2, 443)
        );
        assert_eq!(
            n.resolve("test.", DnsKind::A, Some(0), None),
            Err(NetErr::LimitExceeded)
        );
        assert!(!n.lookup("test.", Some(8), t).unwrap().is_empty());
        assert_eq!(n.lookup("test.", Some(0), t), Err(NetErr::LimitExceeded));
    }

    #[test]
    fn dial_errors() {
        let n = Network::new_root();
        let r = n.restrict(&[], &[], false).unwrap();
        assert!(matches!(
            r.dial_tcp("127.0.0.1:1", Deadline::none()),
            Err(NetErr::PermissionDenied)
        ));
        // Windows retries the SYN for about two seconds before it reports a refusal.
        assert!(
            matches!(n.dial_tcp("127.0.0.1:1", Deadline::after(Duration::from_secs(10))), Err(NetErr::Failed(m)) if m == "connection refused")
        );
        assert!(matches!(
            n.dial_tcp("nonsense", Deadline::none()),
            Err(NetErr::Failed(_))
        ));
    }

    #[test]
    fn closing_a_parent_closes_children() {
        let n = Network::new_root();
        let child = n.restrict(&["localhost"], &[], false).unwrap();
        n.close();
        assert!(child.is_closed());
        assert!(n.restrict(&[], &[], false).is_err());
    }
}
