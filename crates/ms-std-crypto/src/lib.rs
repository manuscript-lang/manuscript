//! `@std/crypto.ms` natives, behaviorally identical to `pkg/runtime/crypto.go`: digests, HMAC,
//! PBKDF2, HKDF, AES-GCM/CTR/CBC and Ed25519, built on RustCrypto.
#![no_std]

extern crate alloc;

pub mod ffi;

use aes::{Aes128, Aes192, Aes256};
use aes_gcm::KeyInit;
use alloc::vec::Vec;
use cipher::block::{BlockModeDecrypt, BlockModeEncrypt};
use cipher::{KeyIvInit, StreamCipher};
use digest::block_api::BlockSizeUser;
use ms_std_core::Fail;
use sha2::Digest;

/// HMAC (RFC 2104) over any digest; RustCrypto's `hmac` does not cover SHA-3.
#[derive(Clone)]
pub struct Hm<D> {
    init: D,
    inner: D,
    outer: D,
}

impl<D: Digest + BlockSizeUser + Clone> Hm<D> {
    pub fn new(key: &[u8]) -> Self {
        let mut k = alloc::vec![0u8; D::block_size()];
        if key.len() > k.len() {
            let d = D::digest(key);
            k[..d.len()].copy_from_slice(&d);
        } else {
            k[..key.len()].copy_from_slice(key);
        }
        let mut init = D::new();
        let mut outer = D::new();
        Digest::update(&mut init, k.iter().map(|b| b ^ 0x36).collect::<Vec<u8>>());
        Digest::update(&mut outer, k.iter().map(|b| b ^ 0x5c).collect::<Vec<u8>>());
        Hm {
            inner: init.clone(),
            init,
            outer,
        }
    }

    fn update(&mut self, data: &[u8]) {
        Digest::update(&mut self.inner, data);
    }

    /// Returns the tag and resets to the keyed initial state.
    fn finish(&mut self) -> Vec<u8> {
        let inner = core::mem::replace(&mut self.inner, self.init.clone()).finalize();
        let mut outer = self.outer.clone();
        Digest::update(&mut outer, inner);
        outer.finalize().to_vec()
    }
}

/// The hash algorithms of `HashAlgorithm`, in declaration order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Alg {
    Md5,
    Sha1,
    Sha224,
    Sha256,
    Sha384,
    Sha512,
    Sha3_256,
    Sha3_384,
    Sha3_512,
}

impl Alg {
    pub fn from_index(i: i64) -> Option<Alg> {
        use Alg::*;
        [
            Md5, Sha1, Sha224, Sha256, Sha384, Sha512, Sha3_256, Sha3_384, Sha3_512,
        ]
        .get(usize::try_from(i).ok()?)
        .copied()
    }

    pub fn digest_size(self) -> usize {
        match self {
            Alg::Md5 => 16,
            Alg::Sha1 => 20,
            Alg::Sha224 => 28,
            Alg::Sha256 | Alg::Sha3_256 => 32,
            Alg::Sha384 | Alg::Sha3_384 => 48,
            Alg::Sha512 | Alg::Sha3_512 => 64,
        }
    }
}

/// Calls `$body` with `$D` bound to the digest type of `$alg`.
macro_rules! with_digest {
    ($alg:expr, $D:ident => $body:expr) => {
        match $alg {
            Alg::Md5 => {
                type $D = md5::Md5;
                $body
            }
            Alg::Sha1 => {
                type $D = sha1::Sha1;
                $body
            }
            Alg::Sha224 => {
                type $D = sha2::Sha224;
                $body
            }
            Alg::Sha256 => {
                type $D = sha2::Sha256;
                $body
            }
            Alg::Sha384 => {
                type $D = sha2::Sha384;
                $body
            }
            Alg::Sha512 => {
                type $D = sha2::Sha512;
                $body
            }
            Alg::Sha3_256 => {
                type $D = sha3::Sha3_256;
                $body
            }
            Alg::Sha3_384 => {
                type $D = sha3::Sha3_384;
                $body
            }
            Alg::Sha3_512 => {
                type $D = sha3::Sha3_512;
                $body
            }
        }
    };
}

pub mod asym;

pub fn digest(alg: Alg, data: &[u8]) -> Vec<u8> {
    with_digest!(alg, D => D::digest(data).to_vec())
}

pub fn hmac(alg: Alg, key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut h = Hasher::new_hmac(alg, key);
    h.update(data);
    h.finish()
}

fn pbkdf2_with<D: Digest + BlockSizeUser + Clone>(
    password: &[u8],
    salt: &[u8],
    rounds: u64,
    out: &mut [u8],
) {
    let base = Hm::<D>::new(password);
    for (i, chunk) in out.chunks_mut(<D as Digest>::output_size()).enumerate() {
        let mut m = base.clone();
        m.update(salt);
        m.update(&(i as u32 + 1).to_be_bytes());
        let mut u = m.finish();
        let mut t = u.clone();
        for _ in 1..rounds {
            let mut m = base.clone();
            m.update(&u);
            u = m.finish();
            t.iter_mut().zip(&u).for_each(|(a, b)| *a ^= b);
        }
        chunk.copy_from_slice(&t[..chunk.len()]);
    }
}

/// PBKDF2-HMAC; `iterations` and `length` must be positive and `length` at most 1 MiB.
pub fn derive_key(
    alg: Alg,
    password: &[u8],
    salt: &[u8],
    iterations: i64,
    length: i64,
) -> Result<Vec<u8>, Fail> {
    if iterations <= 0 || length <= 0 || length > 1_048_576 {
        return Err(Fail::InvalidInput);
    }
    let mut out = alloc::vec![0u8; length as usize];
    with_digest!(alg, D => pbkdf2_with::<D>(password, salt, iterations as u64, &mut out));
    Ok(out)
}

fn hkdf_with<D: Digest + BlockSizeUser + Clone>(
    secret: &[u8],
    salt: &[u8],
    info: &[u8],
    out: &mut [u8],
) {
    // Extract: an empty salt is a zero block of the digest size, which HMAC zero-pads to anyway.
    let mut ex = Hm::<D>::new(salt);
    ex.update(secret);
    let prk = Hm::<D>::new(&ex.finish());
    let mut prev: Vec<u8> = Vec::new();
    for (i, chunk) in out.chunks_mut(<D as Digest>::output_size()).enumerate() {
        let mut m = prk.clone();
        m.update(&prev);
        m.update(info);
        m.update(&[i as u8 + 1]);
        prev = m.finish();
        chunk.copy_from_slice(&prev[..chunk.len()]);
    }
}

/// HKDF extract-and-expand; `length` must be in `1..=255 * digest size`.
pub fn hkdf(
    alg: Alg,
    secret: &[u8],
    salt: &[u8],
    info: &[u8],
    length: i64,
) -> Result<Vec<u8>, Fail> {
    if length <= 0 || length > 255 * alg.digest_size() as i64 {
        return Err(Fail::InvalidInput);
    }
    let mut out = alloc::vec![0u8; length as usize];
    with_digest!(alg, D => hkdf_with::<D>(secret, salt, info, &mut out));
    Ok(out)
}

pub fn constant_time_equal(left: &[u8], right: &[u8]) -> bool {
    use subtle::ConstantTimeEq;
    left.len() == right.len() && bool::from(left.ct_eq(right))
}

/// Errors of the cryptography module beyond `Fail`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CryptoFail {
    InvalidInput,
    Unsupported,
    AuthenticationFailed,
}

impl CryptoFail {
    /// `CryptoError` case index in declaration order: InvalidInput, Unsupported, AuthenticationFailed.
    pub fn status(self) -> u8 {
        match self {
            CryptoFail::InvalidInput => ms_std_core::STATUS_INVALID_INPUT,
            CryptoFail::Unsupported => ms_std_core::STATUS_UNSUPPORTED,
            CryptoFail::AuthenticationFailed => STATUS_AUTHENTICATION_FAILED,
        }
    }
}

/// `CryptoError.AuthenticationFailed`.
pub const STATUS_AUTHENTICATION_FAILED: u8 = 6;

trait Stream {
    fn update(&mut self, data: &[u8]);
    fn finish(&mut self) -> Vec<u8>;
}

struct Plain<D> {
    init: D,
    cur: D,
}

impl<D: Digest + Clone> Stream for Plain<D> {
    fn update(&mut self, data: &[u8]) {
        Digest::update(&mut self.cur, data);
    }
    fn finish(&mut self) -> Vec<u8> {
        core::mem::replace(&mut self.cur, self.init.clone())
            .finalize()
            .to_vec()
    }
}

impl<D: Digest + BlockSizeUser + Clone> Stream for Hm<D> {
    fn update(&mut self, data: &[u8]) {
        Hm::update(self, data);
    }
    fn finish(&mut self) -> Vec<u8> {
        Hm::finish(self)
    }
}

/// Incremental digest or HMAC; `finish` returns the output and resets to the initial state.
pub struct Hasher(alloc::boxed::Box<dyn Stream>);

impl Hasher {
    pub fn new(alg: Alg) -> Hasher {
        with_digest!(alg, D => Hasher(alloc::boxed::Box::new(Plain { init: D::new(), cur: D::new() })))
    }

    pub fn new_hmac(alg: Alg, key: &[u8]) -> Hasher {
        with_digest!(alg, D => Hasher(alloc::boxed::Box::new(Hm::<D>::new(key))))
    }

    pub fn update(&mut self, data: &[u8]) {
        self.0.update(data);
    }

    pub fn finish(&mut self) -> Vec<u8> {
        self.0.finish()
    }
}

// ---- AES ----

fn key_ok(key: &[u8]) -> bool {
    matches!(key.len(), 16 | 24 | 32)
}

macro_rules! with_aes {
    ($key:expr, $A:ident => $body:expr) => {
        match $key.len() {
            16 => {
                type $A = Aes128;
                $body
            }
            24 => {
                type $A = Aes192;
                $body
            }
            _ => {
                type $A = Aes256;
                $body
            }
        }
    };
}

/// AES-GCM seal (12-byte nonce, 16-byte tag appended).
pub fn seal(key: &[u8], nonce: &[u8], plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>, CryptoFail> {
    use aes_gcm::aead::{Aead, Payload};
    if !key_ok(key) || nonce.len() != 12 || plaintext.len() as u64 > ((1u64 << 32) - 2) * 16 {
        return Err(CryptoFail::InvalidInput);
    }
    with_aes!(key, A => {
        let c = <aes_gcm::AesGcm<A, aes_gcm::aead::consts::U12> as KeyInit>::new_from_slice(key)
            .map_err(|_| CryptoFail::InvalidInput)?;
        c.encrypt(<&[u8; 12]>::try_from(nonce).map_err(|_| CryptoFail::InvalidInput)?.into(), Payload { msg: plaintext, aad }).map_err(|_| CryptoFail::InvalidInput)
    })
}

/// AES-GCM open; a bad tag is `AuthenticationFailed`.
pub fn open(
    key: &[u8],
    nonce: &[u8],
    ciphertext: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>, CryptoFail> {
    use aes_gcm::aead::{Aead, Payload};
    if !key_ok(key) || nonce.len() != 12 {
        return Err(CryptoFail::InvalidInput);
    }
    with_aes!(key, A => {
        let c = <aes_gcm::AesGcm<A, aes_gcm::aead::consts::U12> as KeyInit>::new_from_slice(key)
            .map_err(|_| CryptoFail::InvalidInput)?;
        c.decrypt(<&[u8; 12]>::try_from(nonce).map_err(|_| CryptoFail::InvalidInput)?.into(), Payload { msg: ciphertext, aad }).map_err(|_| CryptoFail::AuthenticationFailed)
    })
}

pub fn aes_ctr(key: &[u8], iv: &[u8], data: &[u8]) -> Result<Vec<u8>, CryptoFail> {
    if !key_ok(key) || iv.len() != 16 {
        return Err(CryptoFail::InvalidInput);
    }
    let mut out = data.to_vec();
    with_aes!(key, A => {
        let mut c = ctr::Ctr128BE::<A>::new_from_slices(key, iv).map_err(|_| CryptoFail::InvalidInput)?;
        c.apply_keystream(&mut out);
    });
    Ok(out)
}

pub fn aes_cbc_encrypt(key: &[u8], iv: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, CryptoFail> {
    if !key_ok(key) || iv.len() != 16 {
        return Err(CryptoFail::InvalidInput);
    }
    let pad = 16 - plaintext.len() % 16;
    let mut buf = plaintext.to_vec();
    buf.resize(plaintext.len() + pad, pad as u8);
    with_aes!(key, A => {
        let mut c = cbc::Encryptor::<A>::new_from_slices(key, iv).map_err(|_| CryptoFail::InvalidInput)?;
        for block in buf.as_chunks_mut::<16>().0 {
            c.encrypt_block(block.into());
        }
    });
    Ok(buf)
}

pub fn aes_cbc_decrypt(key: &[u8], iv: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>, CryptoFail> {
    if !key_ok(key)
        || iv.len() != 16
        || ciphertext.is_empty()
        || !ciphertext.len().is_multiple_of(16)
    {
        return Err(CryptoFail::InvalidInput);
    }
    let mut buf = ciphertext.to_vec();
    with_aes!(key, A => {
        let mut c = cbc::Decryptor::<A>::new_from_slices(key, iv).map_err(|_| CryptoFail::InvalidInput)?;
        for block in buf.as_chunks_mut::<16>().0 {
            c.decrypt_block(block.into());
        }
    });
    let pad = usize::from(*buf.last().unwrap_or(&0));
    if pad == 0
        || pad > 16
        || pad > buf.len()
        || buf[buf.len() - pad..]
            .iter()
            .any(|&b| usize::from(b) != pad)
    {
        return Err(CryptoFail::AuthenticationFailed);
    }
    buf.truncate(buf.len() - pad);
    Ok(buf)
}

// ---- Ed25519 ----

pub fn ed25519_sign(seed: &[u8], data: &[u8]) -> Result<Vec<u8>, CryptoFail> {
    use ed25519_dalek::Signer;
    let seed: [u8; 32] = seed.try_into().map_err(|_| CryptoFail::InvalidInput)?;
    Ok(ed25519_dalek::SigningKey::from_bytes(&seed)
        .sign(data)
        .to_bytes()
        .to_vec())
}

pub fn ed25519_public_key(seed: &[u8]) -> Result<Vec<u8>, CryptoFail> {
    let seed: [u8; 32] = seed.try_into().map_err(|_| CryptoFail::InvalidInput)?;
    Ok(ed25519_dalek::SigningKey::from_bytes(&seed)
        .verifying_key()
        .to_bytes()
        .to_vec())
}

pub fn ed25519_verify(key: &[u8], data: &[u8], signature: &[u8]) -> bool {
    use ed25519_dalek::Verifier;
    let (Ok(key), Ok(sig)) = (<[u8; 32]>::try_from(key), <[u8; 64]>::try_from(signature)) else {
        return false;
    };
    let Ok(key) = ed25519_dalek::VerifyingKey::from_bytes(&key) else {
        return false;
    };
    key.verify(data, &ed25519_dalek::Signature::from_bytes(&sig))
        .is_ok()
}
