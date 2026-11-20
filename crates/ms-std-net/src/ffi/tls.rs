//! Natives for `@std/net/tls.ms` and the TLS entry points of `@std/net/net.ms`.
//! ms: domain network

use crate::tls::TlsOptions;
use ms_rt::ffi::{Str, StringList, abi_type};

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
