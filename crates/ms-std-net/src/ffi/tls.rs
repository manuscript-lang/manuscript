//! Shims for `@std/tls.ms` and the TLS entry points of `@std/net.ms`.

use super::net::network;
use super::{finish, handle_ref, new_handle, opt};
use crate::conn::Connection;
use crate::error::{Status, TlsErr};
use crate::tls::{self, TlsOptions};
use ms_rt_abi::{Obj, StrObj, VecVal};
use ms_std_core::{new_string, read_string_list, str_ref, write_bytes, write_string_list};
use std::rc::Rc;

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
}

/// `TlsOptions` as the compiler lays it out for natives.
#[repr(C)]
pub struct TlsOptionsWire {
    pub server_name: *const StrObj,
    pub roots_pem: *const StrObj,
    pub certificate_pem: *const StrObj,
    pub private_key_pem: *const StrObj,
    /// `List[String]`, inline as the compiler lays a list out.
    pub alpn: VecVal,
    pub require_client_certificate: u8,
}

/// # Safety
/// `w` points at a live `TlsOptionsWire` whose strings and list are live.
unsafe fn options(w: *const TlsOptionsWire) -> TlsOptions {
    // SAFETY: caller contract.
    unsafe {
        let w = &*w;
        TlsOptions {
            server_name: str_ref(w.server_name).to_string(),
            roots_pem: str_ref(w.roots_pem).to_string(),
            certificate_pem: str_ref(w.certificate_pem).to_string(),
            private_key_pem: str_ref(w.private_key_pem).to_string(),
            alpn: read_string_list(&w.alpn)
                .into_iter()
                .map(str::to_string)
                .collect(),
            require_client_certificate: w.require_client_certificate != 0,
        }
    }
}

/// `Network.connect_tls(address, server_name, timeout)`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_connect_tls(
    net: *const Obj,
    address: *const StrObj,
    server_name: *const StrObj,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(
            network(net).connect_tls(
                str_ref(address),
                str_ref(server_name),
                opt(has_timeout, timeout),
            ),
            err,
            |c| *out = new_handle::<Rc<Connection>>(c),
        )
    }
}

/// `Network.connect_tls_config(address, options, timeout)`.
///
/// # Safety
/// Pointers per `ABI.md`; `opts` is a live `TlsOptionsWire`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_connect_tls_config(
    net: *const Obj,
    address: *const StrObj,
    opts: *const TlsOptionsWire,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(
            network(net).connect_tls_config(
                str_ref(address),
                &options(opts),
                opt(has_timeout, timeout),
            ),
            err,
            |c| *out = new_handle::<Rc<Connection>>(c),
        )
    }
}

/// `Network.listen_tls(address, options, handshake_timeout)`.
///
/// # Safety
/// As `msrt_net_network_connect_tls_config`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_listen_tls(
    net: *const Obj,
    address: *const StrObj,
    opts: *const TlsOptionsWire,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(
            network(net).listen_tls(str_ref(address), &options(opts), opt(has_timeout, timeout)),
            err,
            |l| *out = new_handle::<Rc<crate::conn::Listener>>(l),
        )
    }
}

/// `TlsInfo` as written for the compiler to copy into the record.
#[repr(C)]
pub struct TlsInfoWire {
    pub version: i64,
    pub cipher_suite: i64,
    pub alpn: *mut StrObj,
    pub verified: u8,
    /// Array of `Bytes` values allocated with `msrt_alloc`; null when empty.
    pub peer_certificates: *mut VecVal,
    pub peer_certificate_count: usize,
}

/// `Connection.tls_info()`: the caller takes the strings and frees the array.
///
/// # Safety
/// `c` is a Connection handle; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_connection_tls_info(c: *const Obj, out: *mut TlsInfoWire) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let conn = handle_ref::<Rc<Connection>>(c);
        match conn.tls_info() {
            Ok(d) => {
                let count = d.peer_certificates.len();
                let certs = if count == 0 {
                    std::ptr::null_mut()
                } else {
                    msrt_alloc(count * std::mem::size_of::<VecVal>()).cast::<VecVal>()
                };
                for (i, der) in d.peer_certificates.iter().enumerate() {
                    write_bytes(certs.add(i), der);
                }
                out.write(TlsInfoWire {
                    version: d.version,
                    cipher_suite: d.cipher_suite,
                    alpn: new_string(&d.alpn),
                    verified: u8::from(d.verified),
                    peer_certificates: certs,
                    peer_certificate_count: count,
                });
                0
            }
            Err(e) => e.code(),
        }
    }
}

/// `CertificateInfo` as written for the compiler to copy into the record.
#[repr(C)]
pub struct CertificateInfoWire {
    pub subject: *mut StrObj,
    pub issuer: *mut StrObj,
    /// `List[String]`.
    pub dns_names: VecVal,
    pub not_before_seconds: i64,
    pub not_before_nanos: i32,
    pub not_after_seconds: i64,
    pub not_after_nanos: i32,
    /// `Bytes`.
    pub der: VecVal,
}

/// `parse_certificates(pem, max_certificates)`: on success `*certs` points at `*count` wire
/// records allocated with `msrt_alloc` (null when empty); the caller takes ownership.
///
/// # Safety
/// `certs` and `count` are writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_tls_parse_certificates(
    pem: *const StrObj,
    has_max: u8,
    max: i64,
    certs: *mut *mut CertificateInfoWire,
    count: *mut usize,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let r = tls::parse_certificates(str_ref(pem), opt(has_max, max));
        match r {
            Ok(list) => {
                *count = list.len();
                *certs = std::ptr::null_mut();
                if !list.is_empty() {
                    let p = msrt_alloc(list.len() * std::mem::size_of::<CertificateInfoWire>())
                        .cast::<CertificateInfoWire>();
                    for (i, c) in list.iter().enumerate() {
                        let slot = p.add(i);
                        (&raw mut (*slot).subject).write(new_string(&c.subject));
                        (&raw mut (*slot).issuer).write(new_string(&c.issuer));
                        write_string_list(&raw mut (*slot).dns_names, c.dns_names.iter());
                        (&raw mut (*slot).not_before_seconds).write(c.not_before.0);
                        (&raw mut (*slot).not_before_nanos).write(c.not_before.1);
                        (&raw mut (*slot).not_after_seconds).write(c.not_after.0);
                        (&raw mut (*slot).not_after_nanos).write(c.not_after.1);
                        write_bytes(&raw mut (*slot).der, &c.der);
                    }
                    *certs = p;
                }
                0
            }
            Err(e) => e.code(),
        }
    }
}

/// `verify_certificates(chain_pem, roots_pem, server_name, now)`.
///
/// # Safety
/// Strings are live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_tls_verify_certificates(
    chain: *const StrObj,
    roots: *const StrObj,
    server_name: *const StrObj,
    now_seconds: i64,
    _now_nanos: i32,
) -> u8 {
    // SAFETY: caller contract.
    let r = unsafe {
        tls::verify_certificates(
            str_ref(chain),
            str_ref(roots),
            str_ref(server_name),
            now_seconds,
        )
    };
    r.err().map_or(0, |e| e.code())
}

/// `TlsError.message()`.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_tls_error_message(status: u8) -> *mut StrObj {
    let e = match status {
        1 => TlsErr::InvalidInput,
        2 => TlsErr::InvalidData,
        3 => TlsErr::LimitExceeded,
        _ => TlsErr::AuthenticationFailed,
    };
    new_string(&e.message())
}

#[cfg(test)]
mod tests {
    use super::*;
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
