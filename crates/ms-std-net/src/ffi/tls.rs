//! Natives for `@std/tls.ms` and the TLS entry points of `@std/net.ms`.

use super::{ConnH, ListenerH, NetH, report};
use crate::error::{Status as _, TlsErr};
use crate::tls::{self, TlsOptions};
use ms_std_core::{
    Bytes, BytesArray, ErrOut, ObjRef, Object, Out, RecArray, StatusCode, Str, StringList,
    abi_record, native,
};

abi_record! {
    /// `TlsOptions` as the compiler lays it out for natives.
    pub struct TlsOptionsWire {
        pub server_name: Str,
        pub roots_pem: Str,
        pub certificate_pem: Str,
        pub private_key_pem: Str,
        pub alpn: StringList,
        pub require_client_certificate: u8,
    }
}

impl TlsOptionsWire {
    /// The options as the TLS module takes them.
    pub fn to_options(&self) -> TlsOptions {
        TlsOptions {
            server_name: self.server_name.as_str().to_string(),
            roots_pem: self.roots_pem.as_str().to_string(),
            certificate_pem: self.certificate_pem.as_str().to_string(),
            private_key_pem: self.private_key_pem.as_str().to_string(),
            alpn: self.alpn.to_vec().into_iter().map(str::to_string).collect(),
            require_client_certificate: self.require_client_certificate != 0,
        }
    }
}

abi_record! {
    /// Negotiated TLS state of a connection.
    pub struct TlsInfoWire {
        pub version: i64,
        pub cipher_suite: i64,
        pub alpn: Str,
        pub verified: u8,
        pub peer_certificates: BytesArray,
    }
}

abi_record! {
    /// One parsed certificate; times are `(seconds, nanoseconds)`.
    pub struct CertificateInfoWire {
        pub subject: Str,
        pub issuer: Str,
        pub dns_names: StringList,
        pub not_before_seconds: i64,
        pub not_before_nanos: i32,
        pub not_after_seconds: i64,
        pub not_after_nanos: i32,
        pub der: Bytes,
    }
}

/// Flattened `Optional[Int]`/`Optional[Duration]` parameter.
fn opt(has: bool, v: i64) -> Option<i64> {
    has.then_some(v)
}

native! {
    /// `Network.connect_tls(address, server_name, timeout)`.
    fn msrt_net_network_connect_tls(
        net: ObjRef<NetH>,
        address: &str,
        server_name: &str,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let c = net.connect_tls(address, server_name, opt(has_timeout, timeout));
        out.write(Object(ConnH(report(c, &err)?)));
        Ok(())
    }

    /// `Network.connect_tls_config(address, options, timeout)`.
    fn msrt_net_network_connect_tls_config(
        net: ObjRef<NetH>,
        address: &str,
        opts: &TlsOptionsWire,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let c = net.connect_tls_config(address, &opts.to_options(), opt(has_timeout, timeout));
        out.write(Object(ConnH(report(c, &err)?)));
        Ok(())
    }

    /// `Network.listen_tls(address, options, timeout)`.
    fn msrt_net_network_listen_tls(
        net: ObjRef<NetH>,
        address: &str,
        opts: &TlsOptionsWire,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<ListenerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let l = net.listen_tls(address, &opts.to_options(), opt(has_timeout, timeout));
        out.write(Object(ListenerH(report(l, &err)?)));
        Ok(())
    }

    /// `Connection.tls_info()`.
    fn msrt_net_connection_tls_info(c: ObjRef<ConnH>) -> Result<TlsInfoWire, StatusCode> {
        let d = c.tls_info().map_err(|e| StatusCode(e.code()))?;
        Ok(TlsInfoWire {
            version: d.version,
            cipher_suite: d.cipher_suite,
            alpn: Str::new(&d.alpn),
            verified: u8::from(d.verified),
            peer_certificates: BytesArray::new(&d.peer_certificates),
        })
    }

    /// `parse_certificates(pem, max)`: the certificates as an array plus its length.
    fn msrt_tls_parse_certificates(
        pem: &str,
        has_max: bool,
        max: i64,
        certs: Out<RecArray<CertificateInfoWire>>,
        count: Out<usize>,
    ) -> Result<(), StatusCode> {
        let list = tls::parse_certificates(pem, opt(has_max, max)).map_err(|e| StatusCode(e.code()))?;
        count.write(list.len());
        certs.write(RecArray(
            list.iter()
                .map(|c| CertificateInfoWire {
                    subject: Str::new(&c.subject),
                    issuer: Str::new(&c.issuer),
                    dns_names: StringList::new(c.dns_names.iter()),
                    not_before_seconds: c.not_before.0,
                    not_before_nanos: c.not_before.1,
                    not_after_seconds: c.not_after.0,
                    not_after_nanos: c.not_after.1,
                    der: Bytes::new(&c.der),
                })
                .collect(),
        ));
        Ok(())
    }

    /// `verify_certificates(chain, roots, server_name, now)`.
    fn msrt_tls_verify_certificates(
        chain: &str,
        roots: &str,
        server_name: &str,
        now_seconds: i64,
        _now_nanos: i32,
    ) -> Result<(), StatusCode> {
        tls::verify_certificates(chain, roots, server_name, now_seconds)
            .map_err(|e| StatusCode(e.code()))
    }

    /// `TlsError.message()` for a status.
    fn msrt_tls_error_message(status: u8) -> String {
        match status {
            1 => TlsErr::InvalidInput,
            2 => TlsErr::InvalidData,
            3 => TlsErr::LimitExceeded,
            _ => TlsErr::AuthenticationFailed,
        }
        .message()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_rt_abi::StrObj;
    use ms_std_core::{new_string, str_ref};
    use std::ptr::null_mut;

    fn s(text: &str) -> *const StrObj {
        new_string(text)
    }

    #[test]
    fn certificate_helpers_through_the_abi() {
        let pem = include_str!("../../testdata/stdlib.test.crt.pem");
        // SAFETY: every pointer is a live runtime object created in this test.
        unsafe {
            let (mut certs, mut count) = (null_mut(), 0usize);
            assert_eq!(
                msrt_tls_parse_certificates(s(pem), 0, 0, &mut certs, &mut count),
                0
            );
            assert_eq!(count, 1);
            assert_eq!((*certs).not_after_seconds, 4_102_444_800);
            assert_eq!(
                msrt_tls_parse_certificates(s(pem), 1, 0, &mut certs, &mut count),
                3
            );
            assert_eq!(
                msrt_tls_verify_certificates(s(pem), s(pem), s("stdlib.test"), 1_700_000_000, 0),
                0
            );
            assert_eq!(
                msrt_tls_verify_certificates(s(pem), s(pem), s("nope.test"), 1_700_000_000, 0),
                4
            );
            let m = msrt_tls_error_message(4);
            assert_eq!(str_ref(m), "TLS: authentication failed");
        }
    }
}
