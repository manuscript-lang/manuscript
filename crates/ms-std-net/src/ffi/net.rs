//! Shims for `@std/net.ms`.

use super::write_record_list;
use super::{finish, handle_ref, new_handle, opt};
use crate::conn::{Connection, Datagrams, Listener};
use crate::error::{NetErr, Status};
use crate::ip::{Cidr, ip_text, normalize, parse_ip};
use crate::net::{DnsKind, Network, root};
use ms_rt_abi::{Obj, StrObj, TypeDesc, VecVal};
use ms_std_core::{
    bytes_ref, new_string, read_string_list, str_ref, write_bytes, write_string_list,
};
use std::net::IpAddr;
use std::rc::Rc;

unsafe extern "C" {
    fn msrt_retain(o: *mut Obj);
}

type NetRef = Rc<Network>;

pub(super) unsafe fn network<'a>(o: *const Obj) -> &'a NetRef {
    // SAFETY: forwarded caller contract (`o` is a Network handle).
    unsafe { handle_ref::<NetRef>(o) }
}

// ------------------------------------------------------------------- IP values

/// `parse_ip(text) -> Result[IpAddress, NetworkError]`.
///
/// # Safety
/// `text` is a live string; `out` and `err` are writable (`err` may be null).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_parse_ip(
    text: *const StrObj,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(parse_ip(str_ref(text)), err, |ip| *out = new_handle(ip)) }
}

/// `parse_cidr(text) -> Result[Cidr, NetworkError]`.
///
/// # Safety
/// As `msrt_net_parse_ip`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_parse_cidr(
    text: *const StrObj,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(Cidr::parse(str_ref(text)), err, |c| *out = new_handle(c)) }
}

/// `contains_ip(cidr, address) -> Result[Bool, NetworkError]`.
///
/// # Safety
/// `cidr` is a Cidr handle, `ip` an IpAddress handle; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_contains_ip(
    cidr: *const Obj,
    ip: *const Obj,
    out: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        *out = handle_ref::<Cidr>(cidr).contains(handle_ref::<IpAddr>(ip)) as u8;
    }
    0
}

/// `IpAddress.text()`.
///
/// # Safety
/// `ip` is an IpAddress handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_ip_address_text(ip: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(&ip_text(unsafe { handle_ref::<IpAddr>(ip) }))
}

/// `IpAddress.family()`: the `IpFamily` case index (`IPv4` = 0, `IPv6` = 1).
///
/// # Safety
/// `ip` is an IpAddress handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_ip_address_family(ip: *const Obj) -> u8 {
    // SAFETY: caller contract.
    u8::from(unsafe { handle_ref::<IpAddr>(ip) }.is_ipv6())
}

/// `Cidr.text()`.
///
/// # Safety
/// `cidr` is a Cidr handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_cidr_text(cidr: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(&unsafe { handle_ref::<Cidr>(cidr) }.text())
}

/// `IpFamily.text()` for a case index.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_net_ip_family_text(family: u8) -> *mut StrObj {
    new_string(if family == 0 { "IPv4" } else { "IPv6" })
}

/// `DnsKind.text()` for a case index.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_net_dns_kind_text(kind: u8) -> *mut StrObj {
    new_string(DnsKind::from_index(kind).map_or("", DnsKind::text))
}

/// `NetworkError.message()` for a status and the `Failed` text (nullable).
///
/// # Safety
/// `failed` is null or a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_error_message(status: u8, failed: *const StrObj) -> *mut StrObj {
    let e = match status {
        1 => NetErr::InvalidInput,
        2 => NetErr::InvalidData,
        3 => NetErr::LimitExceeded,
        4 => NetErr::PermissionDenied,
        5 => NetErr::Unsupported,
        6 => NetErr::Closed,
        7 => NetErr::Timeout,
        // SAFETY: caller contract.
        _ => NetErr::Failed(if failed.is_null() {
            String::new()
        } else {
            // SAFETY: caller contract (`failed` is null or a live string).
            unsafe { str_ref(failed) }.to_string()
        }),
    };
    new_string(&e.message())
}

// --------------------------------------------------------------------- Network

/// `network() -> Network` (+1 reference to the host's root network).
#[unsafe(no_mangle)]
pub extern "C" fn msrt_net_network() -> *mut Obj {
    thread_local! {
        static ROOT_HANDLE: std::cell::Cell<*mut Obj> = const { std::cell::Cell::new(std::ptr::null_mut()) };
    }
    ROOT_HANDLE.with(|h| {
        if h.get().is_null() {
            h.set(new_handle::<NetRef>(root()));
        }
        // SAFETY: the cell owns one count; the caller receives another.
        unsafe { msrt_retain(h.get()) };
        h.get()
    })
}

/// `Network.close()`; closing from a handler of a server this network owns faults.
///
/// # Safety
/// `net` is a Network handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_close(net: *const Obj) {
    // SAFETY: caller contract.
    let net = unsafe { network(net) };
    if crate::http::server::Reactor::get().in_handler_of_network(net) {
        ms_std_core::fault("network cannot close from its own request");
    }
    net.close();
}

/// `Network.connect(address, timeout)`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_connect(
    net: *const Obj,
    address: *const StrObj,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(
            network(net).connect(str_ref(address), opt(has_timeout, timeout)),
            err,
            |c| *out = new_handle::<Rc<Connection>>(c),
        )
    }
}

/// `Network.connect_unix(path, timeout)`.
///
/// # Safety
/// As `msrt_net_network_connect`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_connect_unix(
    net: *const Obj,
    path: *const StrObj,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(
            network(net).connect_unix(str_ref(path), opt(has_timeout, timeout)),
            err,
            |c| *out = new_handle::<Rc<Connection>>(c),
        )
    }
}

/// `Network.listen(address)`.
///
/// # Safety
/// As `msrt_net_network_connect`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_listen(
    net: *const Obj,
    address: *const StrObj,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(network(net).listen(str_ref(address)), err, |l| {
            *out = new_handle::<Rc<Listener>>(l)
        })
    }
}

/// `Network.listen_unix(path)`.
///
/// # Safety
/// As `msrt_net_network_connect`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_listen_unix(
    net: *const Obj,
    path: *const StrObj,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(network(net).listen_unix_socket(str_ref(path)), err, |l| {
            *out = new_handle::<Rc<Listener>>(l)
        })
    }
}

/// `Network.bind_datagram(address)`.
///
/// # Safety
/// As `msrt_net_network_connect`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_bind_datagram(
    net: *const Obj,
    address: *const StrObj,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(network(net).bind_datagram(str_ref(address)), err, |d| {
            *out = new_handle::<Rc<Datagrams>>(d)
        })
    }
}

/// `Network.restrict(hosts, cidrs, allow_listen)`.
///
/// # Safety
/// `hosts` and `cidrs` are live `List[String]` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_restrict(
    net: *const Obj,
    hosts: *const VecVal,
    cidrs: *const VecVal,
    allow_listen: u8,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = network(net).restrict(
            &read_string_list(hosts),
            &read_string_list(cidrs),
            allow_listen != 0,
        );
        finish(r, err, |n| *out = new_handle::<NetRef>(n))
    }
}

/// `Network.with_resolver(address)`.
///
/// # Safety
/// As `msrt_net_network_connect`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_with_resolver(
    net: *const Obj,
    address: *const StrObj,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(network(net).with_resolver(str_ref(address)), err, |n| {
            *out = new_handle::<NetRef>(n)
        })
    }
}

/// `Network.lookup(name, max_records, timeout) -> Result[List[String], NetworkError]`.
///
/// # Safety
/// `out` is writable memory for a `VecVal`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_lookup(
    net: *const Obj,
    name: *const StrObj,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    out: *mut VecVal,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = network(net).lookup(str_ref(name), opt(has_max, max), opt(has_timeout, timeout));
        finish(r, err, |v| write_string_list(out, v))
    }
}

/// One answer of `Network.resolve`; the strings are owned by the caller.
#[repr(C)]
pub struct DnsRecordWire {
    /// `DnsKind` case index (an enum is its tag word).
    pub kind: i64,
    pub value: *mut StrObj,
    pub priority: i64,
    pub weight: i64,
    pub port: i64,
}

/// `Network.resolve(name, kind, max_records, timeout)`: on success `out` is a `List[DnsRecord]`
/// whose elements are `DnsRecordWire` images; `d` describes `DnsRecord`.
///
/// # Safety
/// `out` is writable; `d` describes `DnsRecord`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_resolve(
    net: *const Obj,
    name: *const StrObj,
    kind: u8,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    d: *const TypeDesc,
    out: *mut VecVal,
    err: *mut *mut StrObj,
) -> u8 {
    let Some(kind) = DnsKind::from_index(kind) else {
        return NetErr::InvalidInput.code();
    };
    // SAFETY: caller contract.
    unsafe {
        let r = network(net).resolve(
            str_ref(name),
            kind,
            opt(has_max, max),
            opt(has_timeout, timeout),
        );
        finish(r, err, |list| {
            write_record_list(
                out,
                d,
                list.iter().map(|rec| DnsRecordWire {
                    kind: i64::from(DnsKind::index(rec.kind)),
                    value: new_string(&rec.value),
                    priority: rec.priority,
                    weight: rec.weight,
                    port: rec.port,
                }),
            );
        })
    }
}

// ------------------------------------------------------------------ Connection

unsafe fn connection<'a>(o: *const Obj) -> &'a Rc<Connection> {
    // SAFETY: forwarded caller contract.
    unsafe { handle_ref::<Rc<Connection>>(o) }
}

/// `Connection.close()`.
///
/// # Safety
/// `c` is a Connection handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_close(c: *const Obj) {
    // SAFETY: caller contract.
    unsafe { connection(c) }.close();
}

/// `Connection.local_address()`.
///
/// # Safety
/// `c` is a Connection handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_local_address(c: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(unsafe { connection(c) }.local_address())
}

/// `Connection.peer_address()`.
///
/// # Safety
/// `c` is a Connection handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_peer_address(c: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(unsafe { connection(c) }.peer_address())
}

/// `Connection.read(max_bytes, timeout) -> Result[Optional[Bytes], IoError]`. `present` is 0 at end of stream.
///
/// # Safety
/// `out` is writable memory for a `VecVal`; `present` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_read(
    c: *const Obj,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    out: *mut VecVal,
    present: *mut u8,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = connection(c).read(opt(has_max, max), opt(has_timeout, timeout));
        finish(r, err, |chunk| match chunk {
            Some(bytes) => {
                write_bytes(out, &bytes);
                *present = 1;
            }
            None => *present = 0,
        })
    }
}

/// `Connection.write(data, timeout)` for a `String`.
///
/// # Safety
/// `data` is a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_write(
    c: *const Obj,
    data: *const StrObj,
    has_timeout: u8,
    timeout: i64,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = connection(c).write(str_ref(data).as_bytes(), opt(has_timeout, timeout));
        finish(r, err, |()| {})
    }
}

/// `Connection.write_bytes(data, timeout)`.
///
/// # Safety
/// `data` is a live `Bytes` value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_write_bytes(
    c: *const Obj,
    data: *const VecVal,
    has_timeout: u8,
    timeout: i64,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = connection(c).write(bytes_ref(data), opt(has_timeout, timeout));
        finish(r, err, |()| {})
    }
}

/// `Connection.shutdown_write() -> Result[Unit, NetworkError]`.
///
/// # Safety
/// `c` is a Connection handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_shutdown_write(
    c: *const Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(connection(c).shutdown_write(), err, |()| {}) }
}

// -------------------------------------------------------------------- Listener

unsafe fn listener<'a>(o: *const Obj) -> &'a Rc<Listener> {
    // SAFETY: forwarded caller contract.
    unsafe { handle_ref::<Rc<Listener>>(o) }
}

/// `Listener.accept(timeout)`.
///
/// # Safety
/// `l` is a Listener handle; `out` and `err` writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_listener_accept(
    l: *const Obj,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(listener(l).accept(opt(has_timeout, timeout)), err, |c| {
            *out = new_handle::<Rc<Connection>>(c)
        })
    }
}

/// `Listener.address()`.
///
/// # Safety
/// `l` is a Listener handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_listener_address(l: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(unsafe { listener(l) }.address())
}

/// `Listener.close()`.
///
/// # Safety
/// `l` is a Listener handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_listener_close(l: *const Obj) {
    // SAFETY: caller contract.
    unsafe { listener(l) }.close();
}

// ------------------------------------------------------------------ Datagrams

unsafe fn datagrams<'a>(o: *const Obj) -> &'a Rc<Datagrams> {
    // SAFETY: forwarded caller contract.
    unsafe { handle_ref::<Rc<Datagrams>>(o) }
}

/// `DatagramSocket.address()`.
///
/// # Safety
/// `d` is a DatagramSocket handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_datagram_address(sock: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(unsafe { datagrams(sock) }.address())
}

/// `DatagramSocket.close()`.
///
/// # Safety
/// `sock` is a DatagramSocket handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_datagram_close(sock: *const Obj) {
    // SAFETY: caller contract.
    unsafe { datagrams(sock) }.close();
}

/// `DatagramSocket.receive(max_bytes, timeout)`: the datagram's `data` and `sender`.
///
/// # Safety
/// `data` is writable memory for a `VecVal`; `sender` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_datagram_receive(
    sock: *const Obj,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    data: *mut VecVal,
    sender: *mut *mut StrObj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = datagrams(sock).receive(opt(has_max, max), opt(has_timeout, timeout));
        finish(r, err, |dg| {
            write_bytes(data, &dg.data);
            *sender = new_string(&dg.sender);
        })
    }
}

/// `DatagramSocket.send(data, address, timeout)` for a `String`.
///
/// # Safety
/// `data` and `address` are live strings.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_datagram_send(
    sock: *const Obj,
    data: *const StrObj,
    address: *const StrObj,
    has_timeout: u8,
    timeout: i64,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = datagrams(sock).send(
            str_ref(data).as_bytes(),
            str_ref(address),
            opt(has_timeout, timeout),
        );
        finish(r, err, |()| {})
    }
}

/// `DatagramSocket.send_bytes(data, address, timeout)`.
///
/// # Safety
/// `data` is a live `Bytes` value; `address` a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_datagram_send_bytes(
    sock: *const Obj,
    data: *const VecVal,
    address: *const StrObj,
    has_timeout: u8,
    timeout: i64,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = datagrams(sock).send(bytes_ref(data), str_ref(address), opt(has_timeout, timeout));
        finish(r, err, |()| {})
    }
}

/// Keeps `normalize` linked for IPv4-mapped inputs of future shims.
#[allow(dead_code)]
fn _normalize(ip: IpAddr) -> IpAddr {
    normalize(ip)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem::MaybeUninit;
    use std::ptr::null_mut;

    unsafe fn s(text: &str) -> *mut StrObj {
        new_string(text)
    }

    unsafe fn take(p: *mut StrObj) -> String {
        // SAFETY: test helper over a fresh string.
        unsafe { str_ref(p) }.to_string()
    }

    #[test]
    fn ip_values_cross_the_abi() {
        // SAFETY: every pointer below is a live runtime object created in this test.
        unsafe {
            let mut ip = null_mut();
            let mut cidr = null_mut();
            let mut err = null_mut();
            assert_eq!(
                msrt_net_parse_ip(s("::ffff:192.0.2.1"), &mut ip, &mut err),
                0
            );
            assert_eq!(take(msrt_net_ip_address_text(ip)), "192.0.2.1");
            assert_eq!(msrt_net_ip_address_family(ip), 0);
            assert_eq!(
                msrt_net_parse_cidr(s("192.0.2.3/24"), &mut cidr, &mut err),
                0
            );
            assert_eq!(take(msrt_net_cidr_text(cidr)), "192.0.2.0/24");
            let mut yes = 0;
            assert_eq!(msrt_net_contains_ip(cidr, ip, &mut yes), 0);
            assert_eq!(yes, 1);
            assert_eq!(msrt_net_parse_ip(s("fe80::1%eth0"), &mut ip, &mut err), 2);
            assert_eq!(
                take(msrt_net_error_message(2, null_mut())),
                "network: invalid data"
            );
            assert_eq!(take(msrt_net_error_message(8, s("boom"))), "boom");
            assert_eq!(take(msrt_net_dns_kind_text(3)), "MX");
            assert_eq!(take(msrt_net_ip_family_text(1)), "IPv6");
        }
    }

    #[test]
    fn tcp_round_trip_through_the_abi() {
        // SAFETY: every pointer below is a live runtime object created in this test.
        unsafe {
            let net = msrt_net_network();
            let (mut listener, mut client, mut server) = (null_mut(), null_mut(), null_mut());
            let mut err = null_mut();
            assert_eq!(
                msrt_net_network_listen(net, s("127.0.0.1:0"), &mut listener, &mut err),
                0
            );
            let addr = msrt_net_listener_address(listener);
            assert_eq!(
                msrt_net_network_connect(net, addr, 1, 2_000_000_000, &mut client, &mut err),
                0
            );
            assert_eq!(
                msrt_net_listener_accept(listener, 1, 2_000_000_000, &mut server, &mut err),
                0
            );
            assert_eq!(
                msrt_net_connection_write(client, s("hello"), 1, 2_000_000_000, &mut err),
                0
            );
            let mut out = MaybeUninit::<VecVal>::uninit();
            let mut present = 0u8;
            assert_eq!(
                msrt_net_connection_read(
                    server,
                    1,
                    5,
                    1,
                    2_000_000_000,
                    out.as_mut_ptr(),
                    &mut present,
                    &mut err
                ),
                0
            );
            assert_eq!((present, bytes_ref(out.as_ptr())), (1, &b"hello"[..]));
            assert_eq!(msrt_net_connection_shutdown_write(client, &mut err), 0);
            assert_eq!(
                msrt_net_connection_read(
                    server,
                    0,
                    0,
                    1,
                    2_000_000_000,
                    out.as_mut_ptr(),
                    &mut present,
                    &mut err
                ),
                0
            );
            assert_eq!(present, 0);
            // A timeout reports `Failed("operation timed out")` (IoError case 6).
            assert_eq!(
                msrt_net_connection_read(
                    client,
                    0,
                    0,
                    1,
                    20_000_000,
                    out.as_mut_ptr(),
                    &mut present,
                    &mut err
                ),
                6
            );
            assert_eq!(take(err), "operation timed out");
            assert_eq!(
                take(msrt_net_connection_peer_address(server)),
                take(msrt_net_connection_local_address(client))
            );
            msrt_net_connection_close(client);
            msrt_net_connection_close(server);
            msrt_net_listener_close(listener);
            for h in [client, server, listener, net] {
                ms_rt::obj::msrt_release(h);
            }
        }
    }

    #[test]
    fn restrict_and_resolve_through_the_abi() {
        // SAFETY: every pointer below is a live runtime object created in this test.
        unsafe {
            let net = msrt_net_network();
            let mut child = null_mut();
            let mut err = null_mut();
            let mut hosts = MaybeUninit::<VecVal>::uninit();
            write_string_list(hosts.as_mut_ptr(), ["localhost"]);
            let mut cidrs = MaybeUninit::<VecVal>::uninit();
            write_string_list(cidrs.as_mut_ptr(), ["127.0.0.0/8"]);
            assert_eq!(
                msrt_net_network_restrict(
                    net,
                    hosts.as_ptr(),
                    cidrs.as_ptr(),
                    0,
                    &mut child,
                    &mut err
                ),
                0
            );
            let mut l = null_mut();
            assert_eq!(
                msrt_net_network_listen(child, s("127.0.0.1:0"), &mut l, &mut err),
                4
            );
            let mut out = MaybeUninit::<VecVal>::uninit();
            assert_eq!(
                msrt_net_network_lookup(
                    net,
                    s("127.0.0.1"),
                    0,
                    0,
                    0,
                    0,
                    out.as_mut_ptr(),
                    &mut err
                ),
                0
            );
            assert_eq!(read_string_list(out.as_ptr()), vec!["127.0.0.1"]);
            // A plain-data descriptor of the 40-byte `DnsRecordWire`.
            let desc = ms_rt_abi::TypeDesc {
                size: 40,
                align: 8,
                kind: ms_rt_abi::KIND_POD,
                reserved: 0,
                inner0: std::ptr::null(),
                inner1: std::ptr::null(),
                drop: None,
                copy: None,
                eq: None,
                hash: None,
            };
            let mut records = MaybeUninit::<VecVal>::uninit();
            assert_eq!(
                msrt_net_network_resolve(
                    net,
                    s("127.0.0.1"),
                    0,
                    0,
                    0,
                    0,
                    0,
                    &raw const desc,
                    records.as_mut_ptr(),
                    &mut err
                ),
                0
            );
            let records = records.assume_init();
            assert_eq!(records.len, 1);
            assert_eq!(
                take((*records.ptr.cast::<DnsRecordWire>()).value),
                "127.0.0.1"
            );
            ms_rt::obj::msrt_release(child);
            ms_rt::obj::msrt_release(net);
        }
    }
}
