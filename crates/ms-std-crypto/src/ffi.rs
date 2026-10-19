//! C ABI shims for `@std/crypto.ms`. Symbols are `msrt_crypto_<function>`; fallible functions
//! return a `CryptoError` status (0 ok, 1 InvalidInput, 5 Unsupported, 6 AuthenticationFailed)
//! and write the ok value through `out` only on success. `alg` is the `HashAlgorithm` case index.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{Alg, CryptoFail, Hasher};
use alloc::boxed::Box;
use ms_rt_abi::Obj;
use ms_std_core::{Fail, VecVal, bytes_ref, status_of, write_bytes};

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

unsafe fn crypto_result(r: Result<alloc::vec::Vec<u8>, CryptoFail>, out: *mut VecVal) -> u8 {
    match r {
        Ok(b) => {
            // SAFETY: `out` is writable by the caller contract.
            unsafe { write_bytes(out, &b) };
            0
        }
        Err(e) => e.status(),
    }
}

unsafe fn fail_result(r: Result<alloc::vec::Vec<u8>, Fail>, out: *mut VecVal) -> u8 {
    if let Ok(b) = &r {
        // SAFETY: `out` is writable by the caller contract.
        unsafe { write_bytes(out, b) };
    }
    status_of(&r)
}

unsafe fn digest_bytes(alg: i64, data: *const VecVal, out: *mut VecVal) {
    let alg = Alg::from_index(alg).unwrap_or_else(|| ms_std_core::fault("invalid HashAlgorithm"));
    // SAFETY: `data` is live and `out` is writable.
    unsafe { write_bytes(out, &crate::digest(alg, bytes_ref(data))) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_digest(alg: i64, data: *const VecVal, out: *mut VecVal) {
    // SAFETY: forwarded caller contract.
    unsafe { digest_bytes(alg, data, out) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_hmac(
    alg: i64,
    key: *const VecVal,
    data: *const VecVal,
    out: *mut VecVal,
) -> u8 {
    let Some(alg) = Alg::from_index(alg) else {
        return CryptoFail::Unsupported.status();
    };
    // SAFETY: arguments are live; `out` is writable.
    unsafe { write_bytes(out, &crate::hmac(alg, bytes_ref(key), bytes_ref(data))) };
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_derive_key(
    alg: i64,
    password: *const VecVal,
    salt: *const VecVal,
    iterations: i64,
    length: i64,
    out: *mut VecVal,
) -> u8 {
    let Some(alg) = Alg::from_index(alg) else {
        return CryptoFail::Unsupported.status();
    };
    // SAFETY: arguments are live; `out` is writable.
    unsafe {
        fail_result(
            crate::derive_key(
                alg,
                bytes_ref(password),
                bytes_ref(salt),
                iterations,
                length,
            ),
            out,
        )
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_hkdf(
    alg: i64,
    secret: *const VecVal,
    salt: *const VecVal,
    info: *const VecVal,
    length: i64,
    out: *mut VecVal,
) -> u8 {
    let Some(alg) = Alg::from_index(alg) else {
        return CryptoFail::Unsupported.status();
    };
    // SAFETY: arguments are live; `out` is writable.
    unsafe {
        fail_result(
            crate::hkdf(
                alg,
                bytes_ref(secret),
                bytes_ref(salt),
                bytes_ref(info),
                length,
            ),
            out,
        )
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_constant_time_equal(
    left: *const VecVal,
    right: *const VecVal,
) -> u8 {
    // SAFETY: both are live Bytes values.
    u8::from(crate::constant_time_equal(
        unsafe { bytes_ref(left) },
        unsafe { bytes_ref(right) },
    ))
}

macro_rules! aead {
    ($name:ident, $f:path) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(
            key: *const VecVal,
            nonce: *const VecVal,
            data: *const VecVal,
            aad: *const VecVal,
            out: *mut VecVal,
        ) -> u8 {
            // SAFETY: arguments are live; `out` is writable.
            unsafe {
                crypto_result(
                    $f(
                        bytes_ref(key),
                        bytes_ref(nonce),
                        bytes_ref(data),
                        bytes_ref(aad),
                    ),
                    out,
                )
            }
        }
    };
}
aead!(msrt_crypto_seal, crate::seal);
aead!(msrt_crypto_open, crate::open);

macro_rules! cipher3 {
    ($name:ident, $f:path) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(
            key: *const VecVal,
            iv: *const VecVal,
            data: *const VecVal,
            out: *mut VecVal,
        ) -> u8 {
            // SAFETY: arguments are live; `out` is writable.
            unsafe { crypto_result($f(bytes_ref(key), bytes_ref(iv), bytes_ref(data)), out) }
        }
    };
}
cipher3!(msrt_crypto_aes_ctr, crate::aes_ctr);
cipher3!(msrt_crypto_aes_cbc_encrypt, crate::aes_cbc_encrypt);
cipher3!(msrt_crypto_aes_cbc_decrypt, crate::aes_cbc_decrypt);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_sign(
    seed: *const VecVal,
    data: *const VecVal,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: arguments are live; `out` is writable.
    unsafe { crypto_result(crate::ed25519_sign(bytes_ref(seed), bytes_ref(data)), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_public_key(seed: *const VecVal, out: *mut VecVal) -> u8 {
    // SAFETY: `seed` is live; `out` is writable.
    unsafe { crypto_result(crate::ed25519_public_key(bytes_ref(seed)), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_verify(
    key: *const VecVal,
    data: *const VecVal,
    signature: *const VecVal,
) -> u8 {
    // SAFETY: arguments are live Bytes values.
    u8::from(crate::ed25519_verify(
        unsafe { bytes_ref(key) },
        unsafe { bytes_ref(data) },
        unsafe { bytes_ref(signature) },
    ))
}

/// Runtime handle object behind the `Hasher` interface: header, then the boxed state.
#[repr(C)]
pub struct HasherObj {
    header: Obj,
    state: *mut Hasher,
}

unsafe extern "C" fn hasher_drop(o: *mut Obj) {
    let h = o.cast::<HasherObj>();
    // SAFETY: `o` was created by `new_hasher`; `state` came from `Box::into_raw`.
    unsafe {
        drop(Box::from_raw((*h).state));
        msrt_free(o.cast());
    }
}

unsafe fn new_hasher(state: Hasher) -> *mut HasherObj {
    // SAFETY: allocation sized for `HasherObj`; fully initialised before return.
    unsafe {
        let p = msrt_alloc(core::mem::size_of::<HasherObj>()).cast::<HasherObj>();
        p.write(HasherObj {
            header: Obj {
                rc: 1,
                drop: Some(hasher_drop),
            },
            state: Box::into_raw(Box::new(state)),
        });
        p
    }
}

/// Creates an incremental digest handle (+1).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_hasher_new(alg: i64) -> *mut HasherObj {
    let alg = Alg::from_index(alg).unwrap_or_else(|| ms_std_core::fault("invalid HashAlgorithm"));
    // SAFETY: allocation contract of `new_hasher`.
    unsafe { new_hasher(Hasher::new(alg)) }
}

/// Creates an incremental HMAC handle (+1).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_hmac_hasher_new(
    alg: i64,
    key: *const VecVal,
) -> *mut HasherObj {
    let alg = Alg::from_index(alg).unwrap_or_else(|| ms_std_core::fault("invalid HashAlgorithm"));
    // SAFETY: `key` is live; allocation contract of `new_hasher`.
    unsafe { new_hasher(Hasher::new_hmac(alg, bytes_ref(key))) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_hasher_update(h: *mut HasherObj, data: *const VecVal) {
    // SAFETY: `h` is a live handle from `msrt_crypto_hasher_new`; `data` is live.
    unsafe { (*(*h).state).update(bytes_ref(data)) };
}

/// Returns the digest and resets the handle to its initial state.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_hasher_finish(h: *mut HasherObj, out: *mut VecVal) {
    // SAFETY: `h` is a live handle; `out` is writable.
    unsafe { write_bytes(out, &(*(*h).state).finish()) };
}

// ---- asymmetric ----

/// `ecdsa_generate(curve: Curve)`; `Curve` is passed as its case index.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_ecdsa_generate(curve: i64, out: *mut VecVal) -> u8 {
    let Some(curve) = crate::asym::Curve::from_index(curve) else {
        return CryptoFail::InvalidInput.status();
    };
    // SAFETY: `out` is writable.
    unsafe { crypto_result(crate::asym::ecdsa_generate(curve), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_public_key_der(key: *const VecVal, out: *mut VecVal) -> u8 {
    // SAFETY: `key` is live; `out` is writable.
    unsafe { crypto_result(crate::asym::public_key_der(bytes_ref(key)), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_ecdh_shared_secret(
    private_key: *const VecVal,
    peer: *const VecVal,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: arguments are live; `out` is writable.
    unsafe {
        crypto_result(
            crate::asym::ecdh_shared_secret(bytes_ref(private_key), bytes_ref(peer)),
            out,
        )
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_crypto_rsa_generate(bits: i64, out: *mut VecVal) -> u8 {
    // SAFETY: `out` is writable.
    unsafe { crypto_result(crate::asym::rsa_generate(bits), out) }
}

macro_rules! sign_shim {
    ($name:ident, $f:path) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(
            private_key: *const VecVal,
            alg: i64,
            data: *const VecVal,
            out: *mut VecVal,
        ) -> u8 {
            let Some(alg) = Alg::from_index(alg) else {
                return CryptoFail::Unsupported.status();
            };
            // SAFETY: arguments are live; `out` is writable.
            unsafe { crypto_result($f(bytes_ref(private_key), alg, bytes_ref(data)), out) }
        }
    };
}

macro_rules! verify_shim {
    ($name:ident, $f:path) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(
            public_key: *const VecVal,
            alg: i64,
            data: *const VecVal,
            signature: *const VecVal,
        ) -> u8 {
            let Some(alg) = Alg::from_index(alg) else {
                return 0;
            };
            // SAFETY: arguments are live.
            u8::from(unsafe {
                $f(
                    bytes_ref(public_key),
                    alg,
                    bytes_ref(data),
                    bytes_ref(signature),
                )
            })
        }
    };
}

sign_shim!(msrt_crypto_ecdsa_sign, crate::asym::ecdsa_sign);
sign_shim!(msrt_crypto_rsa_sign, crate::asym::rsa_sign);
sign_shim!(msrt_crypto_rsa_sign_pss, crate::asym::rsa_sign_pss);
sign_shim!(msrt_crypto_rsa_encrypt, crate::asym::rsa_encrypt);
sign_shim!(msrt_crypto_rsa_decrypt, crate::asym::rsa_decrypt);
verify_shim!(msrt_crypto_ecdsa_verify, crate::asym::ecdsa_verify);
verify_shim!(msrt_crypto_rsa_verify, crate::asym::rsa_verify);
verify_shim!(msrt_crypto_rsa_verify_pss, crate::asym::rsa_verify_pss);

#[cfg(test)]
mod tests {
    use super::*;
    use ms_rt as _; // links the msrt_* runtime symbols

    fn bytes(b: &[u8]) -> VecVal {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: write_bytes initialises the whole VecVal.
        unsafe {
            write_bytes(v.as_mut_ptr(), b);
            v.assume_init()
        }
    }

    unsafe fn read(v: &VecVal) -> alloc::vec::Vec<u8> {
        // SAFETY: caller passes an initialised VecVal.
        unsafe { bytes_ref(v) }.to_vec()
    }

    #[test]
    fn hasher_roundtrip() {
        let key = bytes(b"k");
        let a = bytes(b"hello ");
        let b = bytes(b"world");
        let whole = bytes(b"hello world");
        // SAFETY: handles and buffers are live for the calls below.
        unsafe {
            let h = msrt_crypto_hmac_hasher_new(3, &key);
            msrt_crypto_hasher_update(h, &a);
            msrt_crypto_hasher_update(h, &b);
            let mut got = core::mem::MaybeUninit::<VecVal>::uninit();
            msrt_crypto_hasher_finish(h, got.as_mut_ptr());
            let mut want = core::mem::MaybeUninit::<VecVal>::uninit();
            assert_eq!(msrt_crypto_hmac(3, &key, &whole, want.as_mut_ptr()), 0);
            assert_eq!(read(&got.assume_init()), read(&want.assume_init()));
            hasher_drop(h.cast());
        }
    }
    #[test]
    fn asym_roundtrip() {
        let (data, other) = (bytes(b"m"), bytes(b"n"));
        let mut sk = core::mem::MaybeUninit::<VecVal>::uninit();
        let mut pk = core::mem::MaybeUninit::<VecVal>::uninit();
        let mut sig = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: buffers are live and initialised by the calls that fill them.
        unsafe {
            assert_ne!(msrt_crypto_ecdsa_generate(9, sk.as_mut_ptr()), 0);
            assert_eq!(msrt_crypto_ecdsa_generate(0, sk.as_mut_ptr()), 0);
            assert_eq!(msrt_crypto_public_key_der(sk.as_ptr(), pk.as_mut_ptr()), 0);
            assert_eq!(
                msrt_crypto_ecdsa_sign(sk.as_ptr(), 3, &data, sig.as_mut_ptr()),
                0
            );
            assert_eq!(
                msrt_crypto_ecdsa_verify(pk.as_ptr(), 3, &data, sig.as_ptr()),
                1
            );
            assert_eq!(
                msrt_crypto_ecdsa_verify(pk.as_ptr(), 3, &other, sig.as_ptr()),
                0
            );
            assert_eq!(
                msrt_crypto_ecdsa_verify(pk.as_ptr(), 99, &data, sig.as_ptr()),
                0
            );
        }
    }
}
