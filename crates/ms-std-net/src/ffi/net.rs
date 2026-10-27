//! Natives for `@std/net.ms`.

use super::{ConnH, DgramH, IpH, ListenerH, NetH, opt, report};
use crate::error::{NetErr, Status as _};
use crate::ip::{Cidr, ip_text, normalize};
use crate::net::{DnsKind, root};
use ms_rt::ffi::{
    Bytes, ErrOut, ObjRef, Object, Out, RecList, StatusCode, Str, abi_handle, abi_record, native,
};
use ms_rt_abi::STATUS_NONE;
use std::net::IpAddr;

abi_handle!(Cidr);

abi_record! {
    /// One resolved DNS record as compiled code lays out `DnsRecord`.
    pub struct DnsRecordWire {
        pub kind: i64,
        pub value: Str,
        pub priority: i64,
        pub weight: i64,
        pub port: i64,
    }
}

abi_record! {
    /// A received datagram: the payload and the sender's address.
    pub struct DatagramWire {
        pub data: Bytes,
        pub sender: Str,
    }
}

native! {
    // ----------------------------------------------------------------- IP values

    /// `parse_ip(text) -> Result[IpAddress, NetworkError]`.
    fn msrt_net_parse_ip(text: &str, out: Out<Object<IpH>>, err: ErrOut) -> Result<(), StatusCode> {
        out.write(Object(IpH(report(crate::ip::parse_ip(text), &err)?)));
        Ok(())
    }

    /// `parse_cidr(text) -> Result[Cidr, NetworkError]`.
    fn msrt_net_parse_cidr(text: &str, out: Out<Object<Cidr>>, err: ErrOut) -> Result<(), StatusCode> {
        out.write(Object(report(Cidr::parse(text), &err)?));
        Ok(())
    }

    /// `@std/json.ms` reading an `IpAddress` from its string form; the error text is dropped.
    fn msrt_json_dec_ip(text: &str, out: Out<Object<IpH>>) -> Result<(), StatusCode> {
        out.write(Object(IpH(crate::ip::parse_ip(text).map_err(|_| StatusCode(1))?)));
        Ok(())
    }

    /// `@std/json.ms` reading a `Cidr` from its string form; the error text is dropped.
    fn msrt_json_dec_cidr(text: &str, out: Out<Object<Cidr>>) -> Result<(), StatusCode> {
        out.write(Object(Cidr::parse(text).map_err(|_| StatusCode(1))?));
        Ok(())
    }

    /// `contains_ip(cidr, address) -> Result[Bool, NetworkError]`.
    fn msrt_net_contains_ip(cidr: ObjRef<Cidr>, ip: ObjRef<IpH>, out: Out<bool>) -> Result<(), StatusCode> {
        out.write(cidr.contains(&ip));
        Ok(())
    }

    /// `IpAddress.text()`.
    fn msrt_net_ip_address_text(ip: ObjRef<IpH>) -> String {
        ip_text(&ip)
    }

    /// `IpAddress.family()`: the `IpFamily` case index (`IPv4` = 0, `IPv6` = 1).
    fn msrt_net_ip_address_family(ip: ObjRef<IpH>) -> u8 {
        u8::from(ip.is_ipv6())
    }

    /// `Cidr.text()`.
    fn msrt_net_cidr_text(cidr: ObjRef<Cidr>) -> String {
        cidr.text()
    }

    /// `IpFamily.text()` for a case index.
    fn msrt_net_ip_family_text(family: u8) -> &'static str {
        if family == 0 { "IPv4" } else { "IPv6" }
    }

    /// `DnsKind.text()` for a case index.
    fn msrt_net_dns_kind_text(kind: u8) -> &'static str {
        DnsKind::from_index(kind).map_or("", DnsKind::text)
    }

    /// `NetworkError.message()` for a status and the `Failed` text (nullable).
    fn msrt_net_error_message(status: u8, has_failed: bool, failed: &str) -> String {
        let e = match status {
            1 => NetErr::InvalidInput,
            2 => NetErr::InvalidData,
            3 => NetErr::LimitExceeded,
            4 => NetErr::PermissionDenied,
            5 => NetErr::Unsupported,
            6 => NetErr::Closed,
            7 => NetErr::Timeout,
            _ => NetErr::Failed((if has_failed { failed } else { "" }).to_string()),
        };
        e.message()
    }

    // ------------------------------------------------------------------- Network

    /// `network() -> Network` (a new handle on the isolate's root network). No handle is cached
    /// in a thread-local: its destructor would run after a worker's arena is gone.
    fn msrt_net_network() -> Object<NetH> {
        Object(NetH(root()))
    }

    /// `Network.close()`; closing from a handler of a server this network owns faults.
    fn msrt_net_network_close(net: ObjRef<NetH>) -> () {
        if crate::http::server::Reactor::get().in_handler_of_network(&net) {
            ms_rt::ffi::fault("network cannot close from its own request");
        }
        net.close();
    }

    /// `Network.connect(address, timeout)`.
    fn msrt_net_network_connect(
        net: ObjRef<NetH>,
        address: &str,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        ms_rt::dbgf!("[ffi] connect enter {address}");
        let c = report(net.connect(address, opt(has_timeout, timeout)), &err)?;
        out.write(Object(ConnH(c)));
        Ok(())
    }

    /// `Network.connect_unix(path, timeout)`.
    fn msrt_net_network_connect_unix(
        net: ObjRef<NetH>,
        path: &str,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let c = report(net.connect_unix(path, opt(has_timeout, timeout)), &err)?;
        out.write(Object(ConnH(c)));
        Ok(())
    }

    /// `Network.listen(address)`.
    fn msrt_net_network_listen(
        net: ObjRef<NetH>,
        address: &str,
        out: Out<Object<ListenerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(ListenerH(report(net.listen(address), &err)?)));
        Ok(())
    }

    /// `Network.listen_unix(path)`.
    fn msrt_net_network_listen_unix(
        net: ObjRef<NetH>,
        path: &str,
        out: Out<Object<ListenerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(ListenerH(report(net.listen_unix_socket(path), &err)?)));
        Ok(())
    }

    /// `Network.bind_datagram(address)`.
    fn msrt_net_network_bind_datagram(
        net: ObjRef<NetH>,
        address: &str,
        out: Out<Object<DgramH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(DgramH(report(net.bind_datagram(address), &err)?)));
        Ok(())
    }

    /// `Network.restrict(hosts, cidrs, allow_listen)`.
    fn msrt_net_network_restrict(
        net: ObjRef<NetH>,
        hosts: Vec<&str>,
        cidrs: Vec<&str>,
        allow_listen: bool,
        out: Out<Object<NetH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(NetH(report(net.restrict(&hosts, &cidrs, allow_listen), &err)?)));
        Ok(())
    }

    /// `Network.with_resolver(address)`.
    fn msrt_net_network_with_resolver(
        net: ObjRef<NetH>,
        address: &str,
        out: Out<Object<NetH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(NetH(report(net.with_resolver(address), &err)?)));
        Ok(())
    }

    /// `Network.lookup(name, max, timeout)`.
    fn msrt_net_network_lookup(
        net: ObjRef<NetH>,
        name: &str,
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<Vec<String>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let names = net.lookup(name, opt(has_max, max), opt(has_timeout, timeout));
        out.write(report(names, &err)?);
        Ok(())
    }

    /// `Network.resolve(name, kind, max, timeout)`.
    fn msrt_net_network_resolve(
        net: ObjRef<NetH>,
        name: &str,
        kind: i64,
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<RecList<DnsRecordWire>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let Some(kind) = u8::try_from(kind).ok().and_then(DnsKind::from_index) else {
            return Err(StatusCode(NetErr::InvalidInput.code()));
        };
        let list = net
            .0
            .resolve(name, kind, opt(has_max, max), opt(has_timeout, timeout));
        let list = report(list, &err)?;
        out.write(RecList::new(list.iter().map(|rec| DnsRecordWire {
            kind: i64::from(DnsKind::index(rec.kind)),
            value: Str::new(&rec.value),
            priority: rec.priority,
            weight: rec.weight,
            port: rec.port,
        })));
        Ok(())
    }

    // ---------------------------------------------------------------- Connection

    /// `Connection.close()`.
    fn msrt_net_connection_close(c: ObjRef<ConnH>) -> () {
        c.close();
    }

    /// `Connection.local_address()`.
    fn msrt_net_connection_local_address(c: ObjRef<ConnH>) -> String {
        c.local_address().to_string()
    }

    /// `Connection.peer_address()`.
    fn msrt_net_connection_peer_address(c: ObjRef<ConnH>) -> String {
        c.peer_address().to_string()
    }

    /// `Connection.read(max, timeout)`; end of stream is `STATUS_NONE`.
    fn msrt_net_connection_read(
        c: ObjRef<ConnH>,
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<Vec<u8>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        match report(c.read(opt(has_max, max), opt(has_timeout, timeout)), &err)? {
            Some(bytes) => out.write(bytes),
            None => return Err(StatusCode(STATUS_NONE)),
        }
        Ok(())
    }

    /// `Connection.write(data, timeout)`.
    fn msrt_net_connection_write(
        c: ObjRef<ConnH>,
        data: &str,
        has_timeout: bool,
        timeout: i64,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        report(c.write(data.as_bytes(), opt(has_timeout, timeout)), &err)
    }

    /// `Connection.write(data: Bytes, timeout)`.
    fn msrt_net_connection_write_bytes(
        c: ObjRef<ConnH>,
        data: &[u8],
        has_timeout: bool,
        timeout: i64,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        report(c.write(data, opt(has_timeout, timeout)), &err)
    }

    /// `Connection.shutdown_write()`.
    fn msrt_net_connection_shutdown_write(c: ObjRef<ConnH>, err: ErrOut) -> Result<(), StatusCode> {
        report(c.shutdown_write(), &err)
    }

    // ------------------------------------------------------------------ Listener

    /// `Listener.accept(timeout)`.
    fn msrt_net_listener_accept(
        l: ObjRef<ListenerH>,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(ConnH(report(l.accept(opt(has_timeout, timeout)), &err)?)));
        Ok(())
    }

    /// `Listener.address()`.
    fn msrt_net_listener_address(l: ObjRef<ListenerH>) -> String {
        l.address().to_string()
    }

    /// `Listener.close()`.
    fn msrt_net_listener_close(l: ObjRef<ListenerH>) -> () {
        l.close();
    }

    // ----------------------------------------------------------------- Datagrams

    /// `DatagramSocket.address()`.
    fn msrt_net_datagram_address(sock: ObjRef<DgramH>) -> String {
        sock.address().to_string()
    }

    /// `DatagramSocket.close()`.
    fn msrt_net_datagram_close(sock: ObjRef<DgramH>) -> () {
        sock.close();
    }

    /// `DatagramSocket.receive(max, timeout)`.
    fn msrt_net_datagram_receive(
        sock: ObjRef<DgramH>,
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<DatagramWire>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let dg = report(sock.receive(opt(has_max, max), opt(has_timeout, timeout)), &err)?;
        out.write(DatagramWire {
            data: Bytes::new(&dg.data),
            sender: Str::new(&dg.sender),
        });
        Ok(())
    }

    /// `DatagramSocket.send(data, address, timeout)`.
    fn msrt_net_datagram_send(
        sock: ObjRef<DgramH>,
        data: &str,
        address: &str,
        has_timeout: bool,
        timeout: i64,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        report(sock.send(data.as_bytes(), address, opt(has_timeout, timeout)), &err)
    }

    /// `DatagramSocket.send(data: Bytes, address, timeout)`.
    fn msrt_net_datagram_send_bytes(
        sock: ObjRef<DgramH>,
        data: &[u8],
        address: &str,
        has_timeout: bool,
        timeout: i64,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        report(sock.send(data, address, opt(has_timeout, timeout)), &err)
    }
}

#[allow(dead_code)]
fn _normalize(ip: IpAddr) -> IpAddr {
    normalize(ip)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_rt::ffi::{
        bytes_ref, new_string, read_string_list, str_ref, str_release, take_string,
        write_string_list,
    };
    use ms_rt_abi::{StrVal, VecVal};
    use std::mem::MaybeUninit;
    use std::ptr::null_mut;

    /// A string argument that lives for the rest of the test run.
    fn s(text: &str) -> *const StrVal {
        Box::leak(Box::new(new_string(text)))
    }

    fn take_string_val(write: impl FnOnce(*mut StrVal)) -> StrVal {
        let mut out = no_str();
        write(&mut out);
        out
    }

    fn no_str() -> StrVal {
        StrVal::literal(null_mut(), 0)
    }

    /// Reads and releases an owned string.
    unsafe fn take(v: StrVal) -> String {
        // SAFETY: test helper over a fresh string.
        unsafe {
            let text = str_ref(&v).to_string();
            str_release(&v);
            text
        }
    }

    #[test]
    fn ip_values_cross_the_abi() {
        // SAFETY: every pointer below is a live runtime object created in this test.
        unsafe {
            let mut ip = null_mut();
            let mut cidr = null_mut();
            let mut err = no_str();
            assert_eq!(
                msrt_net_parse_ip(s("::ffff:192.0.2.1"), &mut ip, &mut err),
                0
            );
            assert_eq!(
                take_string(|o| msrt_net_ip_address_text(ip, o)),
                "192.0.2.1"
            );
            assert_eq!(msrt_net_ip_address_family(ip), 0);
            assert_eq!(
                msrt_net_parse_cidr(s("192.0.2.3/24"), &mut cidr, &mut err),
                0
            );
            assert_eq!(take_string(|o| msrt_net_cidr_text(cidr, o)), "192.0.2.0/24");
            let mut yes = 0;
            assert_eq!(msrt_net_contains_ip(cidr, ip, &mut yes), 0);
            assert_eq!(yes, 1);
            assert_eq!(msrt_net_parse_ip(s("fe80::1%eth0"), &mut ip, &mut err), 2);
            assert_eq!(
                take_string(|o| msrt_net_error_message(2, 0, s(""), o)),
                "network: invalid data"
            );
            assert_eq!(
                take_string(|o| msrt_net_error_message(8, 1, s("boom"), o)),
                "boom"
            );
            assert_eq!(take_string(|o| msrt_net_dns_kind_text(3, o)), "MX");
            assert_eq!(take_string(|o| msrt_net_ip_family_text(1, o)), "IPv6");
        }
    }

    #[test]
    fn tcp_round_trip_through_the_abi() {
        // SAFETY: every pointer below is a live runtime object created in this test.
        unsafe {
            let net = msrt_net_network();
            let (mut listener, mut client, mut server) = (null_mut(), null_mut(), null_mut());
            let mut err = no_str();
            assert_eq!(
                msrt_net_network_listen(net, s("127.0.0.1:0"), &mut listener, &mut err),
                0
            );
            let addr = Box::leak(Box::new(take_string_val(|o| {
                msrt_net_listener_address(listener, o)
            })));
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
            assert_eq!(
                msrt_net_connection_read(
                    server,
                    1,
                    5,
                    1,
                    2_000_000_000,
                    out.as_mut_ptr(),
                    &mut err
                ),
                0
            );
            assert_eq!(bytes_ref(out.as_ptr()), &b"hello"[..]);
            assert_eq!(msrt_net_connection_shutdown_write(client, &mut err), 0);
            assert_eq!(
                msrt_net_connection_read(
                    server,
                    0,
                    0,
                    1,
                    2_000_000_000,
                    out.as_mut_ptr(),
                    &mut err
                ),
                STATUS_NONE
            );
            // A timeout reports `Failed("operation timed out")` (IoError case 6).
            assert_eq!(
                msrt_net_connection_read(client, 0, 0, 1, 20_000_000, out.as_mut_ptr(), &mut err),
                6
            );
            assert_eq!(take(err), "operation timed out");
            assert_eq!(
                take_string(|o| msrt_net_connection_peer_address(server, o)),
                take_string(|o| msrt_net_connection_local_address(client, o))
            );
            msrt_net_connection_close(client);
            msrt_net_connection_close(server);
            msrt_net_listener_close(listener);
            for h in [client.cast(), server.cast(), listener.cast(), net.cast()] {
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
            let mut err = no_str();
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
                    records.as_mut_ptr(),
                    &mut err
                ),
                0
            );
            let records = records.assume_init();
            assert_eq!(records.len, 1);
            let record = &*(records.ptr as *const DnsRecordWire);
            assert_eq!(take(record.value.as_ptr().read()), "127.0.0.1");
            ms_rt::obj::msrt_release(child.cast());
            ms_rt::obj::msrt_release(net.cast());
        }
    }
}
