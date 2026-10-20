//! C ABI shims for `@std/crypto.ms`. Symbols are `msrt_crypto_<function>`; fallible functions
//! return a `CryptoError` status (0 ok, 1 InvalidInput, 5 Unsupported, 6 AuthenticationFailed)
//! and write the ok value through `out` only on success. `alg` is the `HashAlgorithm` case index.
use crate::{Alg, CryptoFail, Hasher, asym};
use alloc::vec::Vec;
use ms_std_core::{Fail, ObjMut, Object, Status, abi_handle, native};

abi_handle!(Hasher);

/// Either error family a crypto native reports; both map onto `CryptoError` statuses.
pub enum Error {
    Crypto(CryptoFail),
    Core(Fail),
}

impl From<CryptoFail> for Error {
    fn from(e: CryptoFail) -> Error {
        Error::Crypto(e)
    }
}

impl From<Fail> for Error {
    fn from(e: Fail) -> Error {
        Error::Core(e)
    }
}

impl Status for Error {
    fn status(self) -> u8 {
        match self {
            Error::Crypto(e) => e.status(),
            Error::Core(e) => e.status(),
        }
    }
}

impl Status for CryptoFail {
    fn status(self) -> u8 {
        CryptoFail::status(self)
    }
}

fn alg(index: i64) -> Result<Alg, CryptoFail> {
    Alg::from_index(index).ok_or(CryptoFail::Unsupported)
}

/// An unknown algorithm index here is a compiler bug, not a user error.
fn alg_or_fault(index: i64) -> Alg {
    Alg::from_index(index).unwrap_or_else(|| ms_std_core::fault("invalid HashAlgorithm"))
}

native! {
    fn msrt_crypto_digest(alg: i64, data: &[u8]) -> out Vec<u8> {
        crate::digest(alg_or_fault(alg), data)
    }

    fn msrt_crypto_hmac(alg_index: i64, key: &[u8], data: &[u8]) -> Result<Vec<u8>, CryptoFail> {
        Ok(crate::hmac(alg(alg_index)?, key, data))
    }

    fn msrt_crypto_derive_key(
        alg_index: i64,
        password: &[u8],
        salt: &[u8],
        iterations: i64,
        length: i64,
    ) -> Result<Vec<u8>, Error> {
        Ok(crate::derive_key(alg(alg_index)?, password, salt, iterations, length)?)
    }

    fn msrt_crypto_hkdf(
        alg_index: i64,
        secret: &[u8],
        salt: &[u8],
        info: &[u8],
        length: i64,
    ) -> Result<Vec<u8>, Error> {
        Ok(crate::hkdf(alg(alg_index)?, secret, salt, info, length)?)
    }

    fn msrt_crypto_constant_time_equal(left: &[u8], right: &[u8]) -> bool {
        crate::constant_time_equal(left, right)
    }

    fn msrt_crypto_seal(
        key: &[u8],
        nonce: &[u8],
        data: &[u8],
        aad: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        crate::seal(key, nonce, data, aad)
    }

    fn msrt_crypto_open(
        key: &[u8],
        nonce: &[u8],
        data: &[u8],
        aad: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        crate::open(key, nonce, data, aad)
    }

    fn msrt_crypto_aes_ctr(key: &[u8], iv: &[u8], data: &[u8]) -> Result<Vec<u8>, CryptoFail> {
        crate::aes_ctr(key, iv, data)
    }

    fn msrt_crypto_aes_cbc_encrypt(
        key: &[u8],
        iv: &[u8],
        data: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        crate::aes_cbc_encrypt(key, iv, data)
    }

    fn msrt_crypto_aes_cbc_decrypt(
        key: &[u8],
        iv: &[u8],
        data: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        crate::aes_cbc_decrypt(key, iv, data)
    }

    fn msrt_crypto_sign(seed: &[u8], data: &[u8]) -> Result<Vec<u8>, CryptoFail> {
        crate::ed25519_sign(seed, data)
    }

    fn msrt_crypto_public_key(seed: &[u8]) -> Result<Vec<u8>, CryptoFail> {
        crate::ed25519_public_key(seed)
    }

    fn msrt_crypto_verify(key: &[u8], data: &[u8], signature: &[u8]) -> bool {
        crate::ed25519_verify(key, data, signature)
    }

    fn msrt_crypto_hasher_new(alg: i64) -> Object<Hasher> {
        Object(Hasher::new(alg_or_fault(alg)))
    }

    fn msrt_crypto_hmac_hasher_new(alg: i64, key: &[u8]) -> Object<Hasher> {
        Object(Hasher::new_hmac(alg_or_fault(alg), key))
    }

    fn msrt_crypto_hasher_update(h: ObjMut<Hasher>, data: &[u8]) -> () {
        h.0.update(data);
    }

    fn msrt_crypto_hasher_finish(h: ObjMut<Hasher>) -> out Vec<u8> {
        h.0.finish()
    }

    // ---- asymmetric ----

    fn msrt_crypto_ecdsa_generate(curve: i64) -> Result<Vec<u8>, CryptoFail> {
        let curve = asym::Curve::from_index(curve).ok_or(CryptoFail::InvalidInput)?;
        asym::ecdsa_generate(curve)
    }

    fn msrt_crypto_public_key_der(key: &[u8]) -> Result<Vec<u8>, CryptoFail> {
        asym::public_key_der(key)
    }

    fn msrt_crypto_ecdh_shared_secret(
        private_key: &[u8],
        peer: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        asym::ecdh_shared_secret(private_key, peer)
    }

    fn msrt_crypto_rsa_generate(bits: i64) -> Result<Vec<u8>, CryptoFail> {
        asym::rsa_generate(bits)
    }

    fn msrt_crypto_ecdsa_sign(
        private_key: &[u8],
        alg_index: i64,
        data: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        asym::ecdsa_sign(private_key, alg(alg_index)?, data)
    }

    fn msrt_crypto_rsa_sign(
        private_key: &[u8],
        alg_index: i64,
        data: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        asym::rsa_sign(private_key, alg(alg_index)?, data)
    }

    fn msrt_crypto_rsa_sign_pss(
        private_key: &[u8],
        alg_index: i64,
        data: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        asym::rsa_sign_pss(private_key, alg(alg_index)?, data)
    }

    fn msrt_crypto_rsa_encrypt(
        private_key: &[u8],
        alg_index: i64,
        data: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        asym::rsa_encrypt(private_key, alg(alg_index)?, data)
    }

    fn msrt_crypto_rsa_decrypt(
        private_key: &[u8],
        alg_index: i64,
        data: &[u8],
    ) -> Result<Vec<u8>, CryptoFail> {
        asym::rsa_decrypt(private_key, alg(alg_index)?, data)
    }

    fn msrt_crypto_ecdsa_verify(
        public_key: &[u8],
        alg_index: i64,
        data: &[u8],
        signature: &[u8],
    ) -> bool {
        alg(alg_index).is_ok_and(|a| asym::ecdsa_verify(public_key, a, data, signature))
    }

    fn msrt_crypto_rsa_verify(
        public_key: &[u8],
        alg_index: i64,
        data: &[u8],
        signature: &[u8],
    ) -> bool {
        alg(alg_index).is_ok_and(|a| asym::rsa_verify(public_key, a, data, signature))
    }

    fn msrt_crypto_rsa_verify_pss(
        public_key: &[u8],
        alg_index: i64,
        data: &[u8],
        signature: &[u8],
    ) -> bool {
        alg(alg_index).is_ok_and(|a| asym::rsa_verify_pss(public_key, a, data, signature))
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use ms_rt as _;
    use ms_std_core::{VecVal, bytes_ref, write_bytes}; // links the msrt_* runtime symbols
    extern crate std;
    use std::sync::Mutex;

    /// The runtime allocator is not thread safe: tests take turns.
    static SERIAL: Mutex<()> = Mutex::new(());

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
        let _turn = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
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
            ms_rt::obj::msrt_release(h.cast());
        }
    }
    #[test]
    fn asym_roundtrip() {
        let _turn = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
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
