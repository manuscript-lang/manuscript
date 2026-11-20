//! Natives for `@std/net/tls.ms` and the TLS entry points of `@std/net/net.ms`.
//! ms: domain network

use super::{ConnH, ListenerH, NetH, opt, report};
use crate::bound::Bound;
use crate::error::{Status as _, TlsErr};
use crate::tls::TlsOptions;
use ms_rt::ffi::{
    BytesVec, ErrOut, Has, ObjRef, Object, Out, StatusCode, Str, StringList, abi_type, native,
};
use ms_rt_abi::{STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED};

abi_type! {
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

abi_type! {
    /// Negotiated TLS state of a connection, in the field order of `TlsInfo`.
    pub struct TlsInfoWire {
        pub version: i64,
        pub cipher_suite: i64,
        pub alpn: Str,
        pub peer_certificates: BytesVec,
        pub verified: u8,
    }
}

native! {
    /// `Network.connect_tls_config(address, options, timeout)`.
    fn msstd_net_network_connect_tls_config(
        net: ObjRef<NetH>,
        address: &str,
        opts: &TlsOptionsWire,
        has_timeout: Has,
        timeout: i64,
        out: Out<Object<ConnH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let c = net.connect_tls_config(address, &opts.to_options(), opt(*has_timeout, timeout));
        out.write(Object(ConnH(Bound::new(report(c, &err)?))));
        Ok(())
    }

    /// `Network.listen_tls(address, options, timeout)`.
    fn msstd_net_network_listen_tls(
        net: ObjRef<NetH>,
        address: &str,
        opts: &TlsOptionsWire,
        has_timeout: Has,
        timeout: i64,
        out: Out<Object<ListenerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let l = net.listen_tls(address, &opts.to_options(), opt(*has_timeout, timeout));
        out.write(Object(ListenerH(Bound::new(report(l, &err)?))));
        Ok(())
    }

    /// `Connection.tls_info()`.
    fn msstd_net_connection_tls_info(c: ObjRef<ConnH>) -> Result<TlsInfoWire, StatusCode> {
        let d = c.tls_info().map_err(|e| StatusCode(e.code()))?;
        Ok(TlsInfoWire {
            version: d.version,
            cipher_suite: d.cipher_suite,
            alpn: Str::new(&d.alpn),
            verified: u8::from(d.verified),
            peer_certificates: BytesVec::new(&d.peer_certificates),
        })
    }

    /// `TlsError.message()` for a status.
    fn msstd_tls_error_message(status: u8) -> String {
        match status {
            STATUS_INVALID_INPUT => TlsErr::InvalidInput,
            STATUS_INVALID_DATA => TlsErr::InvalidData,
            STATUS_LIMIT_EXCEEDED => TlsErr::LimitExceeded,
            _ => TlsErr::AuthenticationFailed,
        }
        .message()
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
