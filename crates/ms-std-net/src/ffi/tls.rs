//! Natives for `@std/net.ms` and the TLS entry points of `@std/net.ms`.

use super::{ConnH, ListenerH, NetH, opt, report};
use crate::error::{Status as _, TlsErr};
use crate::tls::{self, TlsOptions};
use ms_rt::ffi::{
    Bytes, BytesVec, ErrOut, ObjRef, Object, Out, RecList, StatusCode, Str, StringList, abi_record,
    native,
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
        tls_options(
            &self.server_name,
            &self.roots_pem,
            &self.certificate_pem,
            &self.private_key_pem,
            &self.alpn,
            self.require_client_certificate,
        )
    }
}

/// The options from the fields of `TlsOptions`.
///
/// A record that holds options and has a field after them lists these fields inline instead of
/// nesting [`TlsOptionsWire`]: the compiler packs a nested record's leaves with no tail padding,
/// so the next field sits right behind `require_client_certificate`, where a nested `repr(C)`
/// struct would pad to its alignment first.
pub fn tls_options(
    server_name: &Str,
    roots_pem: &Str,
    certificate_pem: &Str,
    private_key_pem: &Str,
    alpn: &StringList,
    require_client_certificate: u8,
) -> TlsOptions {
    TlsOptions {
        server_name: server_name.as_str().to_string(),
        roots_pem: roots_pem.as_str().to_string(),
        certificate_pem: certificate_pem.as_str().to_string(),
        private_key_pem: private_key_pem.as_str().to_string(),
        alpn: alpn.to_vec().into_iter().map(str::to_string).collect(),
        require_client_certificate: require_client_certificate != 0,
    }
}

abi_record! {
    /// Negotiated TLS state of a connection, in the field order of `TlsInfo`.
    pub struct TlsInfoWire {
        pub version: i64,
        pub cipher_suite: i64,
        pub alpn: Str,
        pub peer_certificates: BytesVec,
        pub verified: u8,
    }
}

abi_record! {
    /// A `Timestamp` at the layout the compiler gives the native time type.
    #[derive(Clone, Copy)]
    pub struct Timestamp {
        pub seconds: i64,
        pub nanos: i64,
    }
}

abi_record! {
    /// `CertificateInfo` at its natural layout.
    pub struct CertificateRec {
        pub subject: Str,
        pub issuer: Str,
        pub dns_names: StringList,
        pub not_before: Timestamp,
        pub not_after: Timestamp,
        pub der: Bytes,
    }
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
            peer_certificates: BytesVec::new(&d.peer_certificates),
        })
    }

    /// `parse_certificates(pem, max)`: the certificates as a `List[CertificateInfo]`.
    fn msrt_tls_parse_certificates(
        pem: &str,
        has_max: bool,
        max: i64,
    ) -> Result<RecList<CertificateRec>, StatusCode> {
        let list = tls::parse_certificates(pem, opt(has_max, max)).map_err(|e| StatusCode(e.code()))?;
        Ok(RecList::new(list.iter().map(|c| CertificateRec {
            subject: Str::new(&c.subject),
            issuer: Str::new(&c.issuer),
            dns_names: StringList::new(c.dns_names.iter()),
            not_before: Timestamp {
                seconds: c.not_before.0,
                nanos: i64::from(c.not_before.1),
            },
            not_after: Timestamp {
                seconds: c.not_after.0,
                nanos: i64::from(c.not_after.1),
            },
            der: Bytes::new(&c.der),
        })))
    }

    /// `verify_certificates(chain, roots, server_name, now)`.
    fn msrt_tls_verify_certificates(
        chain: &str,
        roots: &str,
        server_name: &str,
        now: &Timestamp,
    ) -> Result<(), StatusCode> {
        tls::verify_certificates(chain, roots, server_name, now.seconds)
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
    use ms_rt::ffi::new_string;
    use ms_rt_abi::StrVal;

    fn s(text: &str) -> *const StrVal {
        Box::leak(Box::new(new_string(text)))
    }

    #[test]
    fn certificate_helpers_through_the_abi() {
        let pem = include_str!("../../testdata/stdlib.test.crt.pem");
        // SAFETY: every pointer is a live runtime object created in this test.
        unsafe {
            let mut certs = std::mem::MaybeUninit::<ms_rt_abi::VecVal>::zeroed();
            assert_eq!(
                msrt_tls_parse_certificates(s(pem), 0, 0, certs.as_mut_ptr()),
                0
            );
            let certs = certs.assume_init();
            assert_eq!(certs.len, 1);
            let first = &*certs.ptr.cast::<CertificateRec>();
            assert_eq!(first.not_after.seconds, 4_102_444_800);
            let mut limited = std::mem::MaybeUninit::<ms_rt_abi::VecVal>::zeroed();
            assert_eq!(
                msrt_tls_parse_certificates(s(pem), 1, 0, limited.as_mut_ptr()),
                3
            );
            let now = Timestamp {
                seconds: 1_700_000_000,
                nanos: 0,
            };
            assert_eq!(
                msrt_tls_verify_certificates(s(pem), s(pem), s("stdlib.test"), &now),
                0
            );
            assert_eq!(
                msrt_tls_verify_certificates(s(pem), s(pem), s("nope.test"), &now),
                4
            );
            let m = ms_rt::ffi::take_string(|o| msrt_tls_error_message(4, o));
            assert_eq!(m, "TLS: authentication failed");
        }
    }
}

#[cfg(test)]
mod layout_tests {
    use super::*;

    /// `TlsInfo` is `Int, Int, String, List[Bytes], Bool`: 8 + 8 + 16 + 24 bytes, then the flag.
    #[test]
    fn tls_info_wire_matches_the_record_the_compiler_reads() {
        assert_eq!(core::mem::offset_of!(TlsInfoWire, peer_certificates), 32);
        assert_eq!(core::mem::offset_of!(TlsInfoWire, verified), 56);
        assert_eq!(core::mem::size_of::<TlsInfoWire>(), 64);
    }
}
