//! Shims for `@std/tls.ms` and the TLS entry points of `@std/net.ms`.

use super::net::network;
use super::{finish, handle_ref, new_handle, opt};
use super::{write_bytes_list, write_record_list};
use crate::conn::Connection;
use crate::error::{Status, TlsErr};
use crate::tls::{self, TlsOptions};
use ms_rt_abi::{Obj, StrObj, TypeDesc, VecVal};
use ms_std_core::{new_string, read_string_list, str_ref, write_bytes, write_string_list};
use std::mem::MaybeUninit;
use std::rc::Rc;

/// `TlsOptions` as the compiler lays it out for natives.
#[repr(C)]
pub struct TlsOptionsWire {
    pub server_name: *const StrObj,
    pub roots_pem: *const StrObj,
    pub certificate_pem: *const StrObj,
    pub private_key_pem: *const StrObj,
    /// `List[String]`, inline like every list in a record.
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
            alpn: read_string_list(&raw const w.alpn)
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

/// `TlsInfo` as the compiler lays the record out; the caller takes the string and the list.
#[repr(C)]
pub struct TlsInfoWire {
    pub version: i64,
    pub cipher_suite: i64,
    pub alpn: *mut StrObj,
    /// `List[Bytes]`, inline.
    pub peer_certificates: VecVal,
    pub verified: u8,
}

/// `Connection.tls_info()`: writes a `TlsInfo` record image.
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
                (&raw mut (*out).version).write(d.version);
                (&raw mut (*out).cipher_suite).write(d.cipher_suite);
                (&raw mut (*out).alpn).write(new_string(&d.alpn));
                write_bytes_list(&raw mut (*out).peer_certificates, &d.peer_certificates);
                (&raw mut (*out).verified).write(u8::from(d.verified));
                0
            }
            Err(e) => e.code(),
        }
    }
}

/// `CertificateInfo` as the compiler lays the record out; a `Timestamp` is two words.
#[repr(C)]
pub struct CertificateInfoWire {
    pub subject: *mut StrObj,
    pub issuer: *mut StrObj,
    /// `List[String]`, inline.
    pub dns_names: VecVal,
    pub not_before_seconds: i64,
    pub not_before_nanos: i64,
    pub not_after_seconds: i64,
    pub not_after_nanos: i64,
    /// `Bytes`, inline.
    pub der: VecVal,
}

/// `parse_certificates(pem, max_certificates)`: on success `out` is a `List[CertificateInfo]`
/// whose elements are `CertificateInfoWire` images; `d` describes `CertificateInfo`.
///
/// # Safety
/// `out` is writable; `d` describes `CertificateInfo`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_tls_parse_certificates(
    pem: *const StrObj,
    has_max: u8,
    max: i64,
    d: *const TypeDesc,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        match tls::parse_certificates(str_ref(pem), opt(has_max, max)) {
            Ok(list) => {
                write_record_list(
                    out,
                    d,
                    list.iter().map(|c| {
                        let mut dns = MaybeUninit::<VecVal>::uninit();
                        write_string_list(dns.as_mut_ptr(), c.dns_names.iter());
                        let mut der = MaybeUninit::<VecVal>::uninit();
                        write_bytes(der.as_mut_ptr(), &c.der);
                        CertificateInfoWire {
                            subject: new_string(&c.subject),
                            issuer: new_string(&c.issuer),
                            dns_names: dns.assume_init(),
                            not_before_seconds: c.not_before.0,
                            not_before_nanos: i64::from(c.not_before.1),
                            not_after_seconds: c.not_after.0,
                            not_after_nanos: i64::from(c.not_after.1),
                            der: der.assume_init(),
                        }
                    }),
                );
                0
            }
            Err(e) => e.code(),
        }
    }
}

/// A `Timestamp` record image: seconds and nanoseconds.
#[repr(C)]
pub struct TimestampWire {
    pub seconds: i64,
    pub nanoseconds: i64,
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
    now: *const TimestampWire,
) -> u8 {
    // SAFETY: caller contract.
    let r = unsafe {
        tls::verify_certificates(
            str_ref(chain),
            str_ref(roots),
            str_ref(server_name),
            (*now).seconds,
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

    fn s(text: &str) -> *const StrObj {
        new_string(text)
    }

    #[test]
    fn certificate_helpers_through_the_abi() {
        let pem = include_str!("../../testdata/stdlib.test.crt.pem");
        // SAFETY: every pointer is a live runtime object created in this test.
        unsafe {
            // A plain-data descriptor of the `CertificateInfoWire` image.
            let desc = ms_rt_abi::TypeDesc {
                size: std::mem::size_of::<CertificateInfoWire>() as u32,
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
            let mut certs = MaybeUninit::<VecVal>::uninit();
            assert_eq!(
                msrt_tls_parse_certificates(s(pem), 0, 0, &raw const desc, certs.as_mut_ptr()),
                0
            );
            let certs = certs.assume_init();
            assert_eq!(certs.len, 1);
            let first = certs.ptr.cast::<CertificateInfoWire>();
            assert_eq!((*first).not_after_seconds, 4_102_444_800);
            let mut limited = MaybeUninit::<VecVal>::uninit();
            assert_eq!(
                msrt_tls_parse_certificates(s(pem), 1, 0, &raw const desc, limited.as_mut_ptr()),
                3
            );
            let now = TimestampWire {
                seconds: 1_700_000_000,
                nanoseconds: 0,
            };
            assert_eq!(
                msrt_tls_verify_certificates(s(pem), s(pem), s("stdlib.test"), &now),
                0
            );
            assert_eq!(
                msrt_tls_verify_certificates(s(pem), s(pem), s("nope.test"), &now),
                4
            );
            let m = msrt_tls_error_message(4);
            assert_eq!(str_ref(m), "TLS: authentication failed");
        }
    }
}
