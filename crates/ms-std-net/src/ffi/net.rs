//! Natives for `@std/net/net.ms`.
//! ms: domain network

use super::tls::TlsOptionsWire;
use super::{ConnH, DgramH, ListenerH, NetH, opt, report};
use crate::bound::Bound;
use crate::error::NetErr;
use crate::ip::normalize;
use crate::net::root;
#[cfg(test)]
use ms_rt::ffi::ErrSlot;
#[cfg(test)]
use ms_rt::ffi::HasRaw;
use ms_rt::ffi::{
    Bytes, ErrOut, Has, ObjRef, Object, Out, StatusCode, Str, abi_type,
    native,
};
use ms_rt_abi::{
    STATUS_CLOSED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_NONE,
    STATUS_PERMISSION_DENIED, STATUS_TIMEOUT, STATUS_UNSUPPORTED,
};
use std::net::IpAddr;

abi_type! {
    /// A received datagram: the payload and the sender's address.
    pub struct DatagramWire {
        pub data: Bytes,
        pub sender: Str,
    }
}

native! {
    /// `NetworkError.message()` for a status and the `Failed` text (nullable).
    fn msstd_net_error_message(status: u8, has_failed: Has, failed: &str) -> String {
        let e = match status {
            STATUS_INVALID_INPUT => NetErr::InvalidInput,
            STATUS_INVALID_DATA => NetErr::InvalidData,
            STATUS_LIMIT_EXCEEDED => NetErr::LimitExceeded,
            STATUS_PERMISSION_DENIED => NetErr::PermissionDenied,
            STATUS_UNSUPPORTED => NetErr::Unsupported,
            STATUS_CLOSED => NetErr::Closed,
            STATUS_TIMEOUT => NetErr::Timeout,
            _ => NetErr::Failed((if *has_failed { failed } else { "" }).to_string()),
        };
        e.message()
    }

    // ------------------------------------------------------------------- Network

    /// `network() -> Network` (a new handle on the isolate's root network). No handle is cached
    /// in a thread-local: its destructor would run after a worker's arena is gone.
    fn msstd_net_network() -> Object<NetH> {
        Object(NetH(root()))
    }

    /// `Network.close()`; closing from a handler of a server this network owns faults.
    fn msstd_net_network_close(net: ObjRef<NetH>) -> () {
        if crate::http::server::Reactor::get().in_handler_of_network(&net) {
            ms_rt::ffi::fault("network cannot close from its own request");
        }
        net.close();
    }

    /// `Network.connect(address, timeout)`.
    fn msstd_net_network_connect(
        net: ObjRef<NetH>,
        address: &str,
        has_timeout: Has,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let c = report(net.connect(address, opt(*has_timeout, timeout)), &err)?;
        out.write(Object(ConnH(Bound::new(c))));
        Ok(())
    }

    /// `Network.connect_unix(path, timeout)`.
    fn msstd_net_network_connect_unix(
        net: ObjRef<NetH>,
        path: &str,
        has_timeout: Has,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let c = report(net.connect_unix(path, opt(*has_timeout, timeout)), &err)?;
        out.write(Object(ConnH(Bound::new(c))));
        Ok(())
    }

    /// `Network.listen(address)`.
    fn msstd_net_network_listen(
        net: ObjRef<NetH>,
        address: &str,
        out: Out<Object<ListenerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(ListenerH(Bound::new(report(net.listen(address), &err)?))));
        Ok(())
    }

    /// `Network.listen_unix(path)`.
    fn msstd_net_network_listen_unix(
        net: ObjRef<NetH>,
        path: &str,
        out: Out<Object<ListenerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(ListenerH(Bound::new(report(net.listen_unix_socket(path), &err)?))));
        Ok(())
    }

    /// `Network.bind_datagram(address)`.
    fn msstd_net_network_bind_datagram(
        net: ObjRef<NetH>,
        address: &str,
        out: Out<Object<DgramH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(DgramH(Bound::new(report(net.bind_datagram(address), &err)?))));
        Ok(())
    }

    /// `Network.restrict(hosts, cidrs, allow_listen)`.
    fn msstd_net_network_restrict(
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
    fn msstd_net_network_with_resolver(
        net: ObjRef<NetH>,
        address: &str,
        out: Out<Object<NetH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(NetH(report(net.with_resolver(address), &err)?)));
        Ok(())
    }

    // ---------------------------------------------------------------- Connection

    /// `Connection.close()`.
    fn msstd_net_connection_close(c: ObjRef<ConnH>) -> () {
        c.close();
    }

    /// Another handle on the same connection, for the other end of a `Connection` record.
    fn msstd_net_connection_share(c: ObjRef<ConnH>) -> Object<ConnH> {
        c.add_end();
        Object(ConnH(c.0.0.clone()))
    }

    /// Another handle on the same connection that is not a stream end, for upgrading it.
    fn msstd_net_connection_alias(c: ObjRef<ConnH>) -> Object<ConnH> {
        Object(ConnH(c.0.0.clone()))
    }

    /// Closes the connection when `c` is its last open end; an end that closes first leaves it open for the other.
    fn msstd_net_connection_close_if_last(c: ObjRef<ConnH>) -> () {
        c.close_end();
    }

    /// `start_tls(connection, options, timeout)`: the TLS connection that replaces `c`.
    fn msstd_net_connection_start_tls(
        c: ObjRef<ConnH>,
        opts: &TlsOptionsWire,
        has_timeout: Has,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let upgraded = c.start_tls(&opts.to_options(), opt(*has_timeout, timeout));
        out.write(Object(ConnH(Bound::new(report(upgraded, &err)?))));
        Ok(())
    }

    /// `accept_tls(connection, options, timeout)`: the TLS connection that replaces `c`.
    fn msstd_net_connection_accept_tls(
        c: ObjRef<ConnH>,
        opts: &TlsOptionsWire,
        has_timeout: Has,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let upgraded = c.accept_tls(&opts.to_options(), opt(*has_timeout, timeout));
        out.write(Object(ConnH(Bound::new(report(upgraded, &err)?))));
        Ok(())
    }

    /// `Connection.local_address()`.
    fn msstd_net_connection_local_address(c: ObjRef<ConnH>) -> String {
        c.local_address().to_string()
    }

    /// `Connection.peer_address()`.
    fn msstd_net_connection_peer_address(c: ObjRef<ConnH>) -> String {
        c.peer_address().to_string()
    }

    /// `Connection.read(max, timeout)`; end of stream is `STATUS_NONE`.
    fn msstd_net_connection_read(
        c: ObjRef<ConnH>,
        has_max: Has,
        max: i64,
        has_timeout: Has,
        timeout: i64,
        out: Out<Vec<u8>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        match report(c.read(opt(*has_max, max), opt(*has_timeout, timeout)), &err)? {
            Some(bytes) => out.write(bytes),
            None => return Err(StatusCode(STATUS_NONE)),
        }
        Ok(())
    }

    /// `Connection.write(data: Bytes, timeout)`.
    fn msstd_net_connection_write_bytes(
        c: ObjRef<ConnH>,
        data: &[u8],
        has_timeout: Has,
        timeout: i64,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        report(c.write(data, opt(*has_timeout, timeout)), &err)
    }

    /// `Connection.shutdown_write()`.
    fn msstd_net_connection_shutdown_write(c: ObjRef<ConnH>, err: ErrOut) -> Result<(), StatusCode> {
        report(c.shutdown_write(), &err)
    }

    // ------------------------------------------------------------------ Listener

    /// `Listener.accept(timeout)`.
    fn msstd_net_listener_accept(
        l: ObjRef<ListenerH>,
        has_timeout: Has,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(ConnH(Bound::new(report(l.accept(opt(*has_timeout, timeout)), &err)?))));
        Ok(())
    }

    /// Waits for the next connection and returns its socket handle without wrapping it, for
    /// `connection_adopt` on any thread. A TLS listener refuses.
    fn msstd_net_listener_accept_raw(
        l: ObjRef<ListenerH>,
        has_timeout: Has,
        timeout: i64,
        out: Out<i64>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(report(l.accept_raw(opt(*has_timeout, timeout)), &err)?);
        Ok(())
    }

    /// Wraps a socket handle `accept_raw` returned as a connection of the host network on this
    /// thread, which then owns it.
    fn msstd_net_connection_adopt(raw: i64, out: Out<Object<ConnH>>, err: ErrOut) -> Result<(), StatusCode> {
        let sock = report(crate::conn::take_raw_handle(raw).ok_or(NetErr::InvalidInput), &err)?;
        let wrap = Box::new(|s| Ok(Box::new(crate::conn::Plain::new(s)) as Box<dyn crate::conn::Io>));
        out.write(Object(ConnH(Bound::new(report(root().adopt(sock, wrap), &err)?))));
        Ok(())
    }

    /// Closes a socket handle `accept_raw` returned that was never adopted.
    fn msstd_net_pending_release(raw: i64) -> () {
        drop(crate::conn::take_raw_handle(raw));
    }

    /// Another handle on the same listener, for a promise that accepts on it. Dropping the handle
    /// leaves the listener open; `Listener.close()` stops it.
    fn msstd_net_listener_share(l: ObjRef<ListenerH>) -> Object<ListenerH> {
        Object(ListenerH(l.0.0.clone()))
    }

    /// `Listener.address()`.
    fn msstd_net_listener_address(l: ObjRef<ListenerH>) -> String {
        l.address().to_string()
    }

    /// `Listener.close()`.
    fn msstd_net_listener_close(l: ObjRef<ListenerH>) -> () {
        l.close();
    }

    // ----------------------------------------------------------------- Datagrams

    /// `DatagramSocket.address()`.
    fn msstd_net_datagram_address(sock: ObjRef<DgramH>) -> String {
        sock.address().to_string()
    }

    /// `DatagramSocket.close()`.
    fn msstd_net_datagram_close(sock: ObjRef<DgramH>) -> () {
        sock.close();
    }

    /// Another handle on the same socket, for the other end of a `DatagramSocket` record.
    fn msstd_net_datagram_share(sock: ObjRef<DgramH>) -> Object<DgramH> {
        Object(DgramH(sock.0.0.clone()))
    }

    /// Closes the socket when `sock` is its last handle.
    fn msstd_net_datagram_close_if_last(sock: ObjRef<DgramH>) -> () {
        if std::rc::Rc::strong_count(&sock.0.0) == 1 {
            sock.close();
        }
    }

    /// `DatagramSocket.receive(max, timeout)`.
    fn msstd_net_datagram_receive(
        sock: ObjRef<DgramH>,
        has_max: Has,
        max: i64,
        has_timeout: Has,
        timeout: i64,
        out: Out<DatagramWire>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let dg = report(sock.receive(opt(*has_max, max), opt(*has_timeout, timeout)), &err)?;
        out.write(DatagramWire {
            data: Bytes::new(&dg.data),
            sender: Str::new(&dg.sender),
        });
        Ok(())
    }

    /// `DatagramSocket.send(data: Bytes, address, timeout)`.
    fn msstd_net_datagram_send_bytes(
        sock: ObjRef<DgramH>,
        data: &[u8],
        address: &str,
        has_timeout: Has,
        timeout: i64,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        report(sock.send(data, address, opt(*has_timeout, timeout)), &err)
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
        bytes_ref, new_string, str_ref, str_release, take_string,
        write_string_list,
    };
    use ms_rt_abi::{STATUS_FAILED, STATUS_INVALID_DATA, STATUS_PERMISSION_DENIED, StrVal, VecVal};
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
    fn error_messages_cross_the_abi() {
        // SAFETY: the strings are fresh and released by the helpers.
        unsafe {
            assert_eq!(
                take_string(|o| msstd_net_error_message(STATUS_INVALID_DATA, HasRaw(0), s(""), o)),
                "network: invalid data"
            );
            assert_eq!(
                take_string(|o| msstd_net_error_message(STATUS_FAILED, HasRaw(1), s("boom"), o)),
                "boom"
            );
        }
    }

    #[test]
    fn tcp_round_trip_through_the_abi() {
        // SAFETY: every pointer below is a live runtime object created in this test.
        unsafe {
            let net = msstd_net_network();
            let (mut listener, mut client, mut server) = (null_mut(), null_mut(), null_mut());
            let mut err = no_str();
            assert_eq!(
                msstd_net_network_listen(net, s("127.0.0.1:0"), &mut listener, ErrSlot(&mut err)),
                0
            );
            let addr = Box::leak(Box::new(take_string_val(|o| {
                msstd_net_listener_address(listener, o)
            })));
            assert_eq!(
                msstd_net_network_connect(
                    net,
                    addr,
                    HasRaw(1),
                    2_000_000_000,
                    &mut client,
                    ErrSlot(&mut err)
                ),
                0
            );
            assert_eq!(
                msstd_net_listener_accept(
                    listener,
                    HasRaw(1),
                    2_000_000_000,
                    &mut server,
                    ErrSlot(&mut err)
                ),
                0
            );
            let mut hello = MaybeUninit::<VecVal>::uninit();
            ms_rt::ffi::write_bytes(hello.as_mut_ptr(), b"hello");
            assert_eq!(
                msstd_net_connection_write_bytes(
                    client,
                    hello.as_ptr(),
                    HasRaw(1),
                    2_000_000_000,
                    ErrSlot(&mut err)
                ),
                0
            );
            let mut out = MaybeUninit::<VecVal>::uninit();
            assert_eq!(
                msstd_net_connection_read(
                    server,
                    ms_rt_abi::HasRaw(1),
                    5,
                    ms_rt_abi::HasRaw(1),
                    2_000_000_000,
                    out.as_mut_ptr(),
                    ErrSlot(&mut err)
                ),
                0
            );
            assert_eq!(bytes_ref(out.as_ptr()), &b"hello"[..]);
            assert_eq!(
                msstd_net_connection_shutdown_write(client, ErrSlot(&mut err)),
                0
            );
            assert_eq!(
                msstd_net_connection_read(
                    server,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(1),
                    2_000_000_000,
                    out.as_mut_ptr(),
                    ErrSlot(&mut err)
                ),
                STATUS_NONE
            );
            // A timeout reports `Failed("operation timed out")`.
            assert_eq!(
                msstd_net_connection_read(
                    client,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(1),
                    20_000_000,
                    out.as_mut_ptr(),
                    ErrSlot(&mut err)
                ),
                STATUS_FAILED
            );
            assert_eq!(take(err), "operation timed out");
            assert_eq!(
                take_string(|o| msstd_net_connection_peer_address(server, o)),
                take_string(|o| msstd_net_connection_local_address(client, o))
            );
            msstd_net_connection_close(client);
            msstd_net_connection_close(server);
            msstd_net_listener_close(listener);
            for h in [client.cast(), server.cast(), listener.cast(), net.cast()] {
                ms_rt::obj::msrt_obj_drop(h);
            }
        }
    }

    #[test]
    fn restrict_through_the_abi() {
        // SAFETY: every pointer below is a live runtime object created in this test.
        unsafe {
            let net = msstd_net_network();
            let mut child = null_mut();
            let mut err = no_str();
            let mut hosts = MaybeUninit::<VecVal>::uninit();
            write_string_list(hosts.as_mut_ptr(), ["localhost"]);
            let mut cidrs = MaybeUninit::<VecVal>::uninit();
            write_string_list(cidrs.as_mut_ptr(), ["127.0.0.0/8"]);
            assert_eq!(
                msstd_net_network_restrict(
                    net,
                    hosts.as_ptr(),
                    cidrs.as_ptr(),
                    0,
                    &mut child,
                    ErrSlot(&mut err)
                ),
                0
            );
            let mut l = null_mut();
            assert_eq!(
                msstd_net_network_listen(child, s("127.0.0.1:0"), &mut l, ErrSlot(&mut err)),
                STATUS_PERMISSION_DENIED
            );
            ms_rt::obj::msrt_obj_drop(child.cast());
            ms_rt::obj::msrt_obj_drop(net.cast());
        }
    }
}
