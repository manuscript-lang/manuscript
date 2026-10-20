//! Asymmetric operations of `@std/crypto.ms`: ECDSA and ECDH over P-256/384/521, X25519, and RSA
//! (PKCS#1 v1.5, PSS, OAEP), with PKCS#8 / PKIX DER keys.
use crate::{Alg, CryptoFail};
use alloc::vec::Vec;
use getrandom::SysRng;
use rand_core::UnwrapErr;
use rsa::pkcs8::{DecodePrivateKey, DecodePublicKey, EncodePrivateKey, EncodePublicKey};
use rsa::{RsaPrivateKey, RsaPublicKey};

/// The elliptic curves of `Curve`, in declaration order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Curve {
    P256,
    P384,
    P521,
    X25519,
}

impl Curve {
    pub fn from_index(i: i64) -> Option<Curve> {
        [Curve::P256, Curve::P384, Curve::P521, Curve::X25519]
            .get(usize::try_from(i).ok()?)
            .copied()
    }
}

type R<T> = Result<T, CryptoFail>;

const fn invalid<T>() -> R<T> {
    Err(CryptoFail::InvalidInput)
}

fn rng() -> UnwrapErr<SysRng> {
    UnwrapErr(SysRng)
}

/// Left-pads (or truncates) a digest to `n` bytes so that it reads as the same integer the Go
/// implementation derives with `hashToNat`.
fn fit_digest(d: &[u8], n: usize) -> Vec<u8> {
    if d.len() >= n {
        d[..n].to_vec()
    } else {
        let mut v = alloc::vec![0u8; n - d.len()];
        v.extend_from_slice(d);
        v
    }
}

// ---- fixed-shape PKCS#8 / PKIX encodings for the 32-byte curve25519 keys ----

const X25519_OID: [u8; 3] = [0x2b, 0x65, 0x6e];
const ED25519_OID: [u8; 3] = [0x2b, 0x65, 0x70];

fn pkcs8_25519(oid: [u8; 3], key: &[u8; 32]) -> Vec<u8> {
    let mut v = alloc::vec![0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03];
    v.extend_from_slice(&oid);
    v.extend_from_slice(&[0x04, 0x22, 0x04, 0x20]);
    v.extend_from_slice(key);
    v
}

fn spki_25519(oid: [u8; 3], key: &[u8; 32]) -> Vec<u8> {
    let mut v = alloc::vec![0x30, 0x2a, 0x30, 0x05, 0x06, 0x03];
    v.extend_from_slice(&oid);
    v.extend_from_slice(&[0x03, 0x21, 0x00]);
    v.extend_from_slice(key);
    v
}

fn parse_pkcs8_25519(oid: [u8; 3], der: &[u8]) -> Option<[u8; 32]> {
    let want = pkcs8_25519(oid, &[0; 32]);
    (der.len() == want.len() && der[..16] == want[..16])
        .then(|| <[u8; 32]>::try_from(&der[16..]).ok())
        .flatten()
}

fn parse_spki_25519(oid: [u8; 3], der: &[u8]) -> Option<[u8; 32]> {
    let want = spki_25519(oid, &[0; 32]);
    (der.len() == want.len() && der[..12] == want[..12])
        .then(|| <[u8; 32]>::try_from(&der[12..]).ok())
        .flatten()
}

// ---- keys ----

macro_rules! ec_curve {
    ($m:ident, $c:ident, $curve:ident, $field:expr) => {
        mod $m {
            use super::*;
            use $c::ecdsa::{SigningKey, VerifyingKey};
            use $c::pkcs8::{DecodePrivateKey, DecodePublicKey, EncodePrivateKey, EncodePublicKey};
            use $c::ecdsa::signature::hazmat::{PrehashVerifier, RandomizedPrehashSigner};
            use $c::elliptic_curve::Generate;
            use $c::{PublicKey, SecretKey};

            pub fn generate() -> R<Vec<u8>> {
                let k = SecretKey::generate_from_rng(&mut rng());
                k.to_pkcs8_der().map(|d| d.as_bytes().to_vec()).or(invalid())
            }

            pub fn parse_private(der: &[u8]) -> Option<SecretKey> {
                // Go derives the public key from the scalar and ignores one embedded in the key.
                if let Ok(k) = SecretKey::from_pkcs8_der(der) {
                    return Some(k);
                }
                // The identifiers still have to name this curve: only the embedded key is optional.
                let info = $c::pkcs8::PrivateKeyInfoRef::try_from(der).ok()?;
                info.algorithm
                    .assert_oids(sec1::ALGORITHM_OID, <$c::$curve as $c::pkcs8::AssociatedOid>::OID)
                    .ok()?;
                let ec = sec1::EcPrivateKey::try_from(info.private_key.as_bytes()).ok()?;
                SecretKey::from_slice(ec.private_key).ok()
            }

            pub fn parse_public(der: &[u8]) -> Option<PublicKey> {
                // Go's parser only accepts uncompressed points.
                let k = PublicKey::from_public_key_der(der).ok()?;
                let spki = k.to_public_key_der().ok()?;
                (spki.as_bytes() == der).then_some(k)
            }

            pub fn public_key(k: &SecretKey) -> R<Vec<u8>> {
                k.public_key().to_public_key_der().map(|d| d.as_bytes().to_vec()).or(invalid())
            }

            pub fn sign(k: &SecretKey, digest: &[u8]) -> R<Vec<u8>> {
                let sk = SigningKey::from(k.clone());
                let prehash = fit_digest(digest, $field);
                let sig: $c::ecdsa::DerSignature =
                    sk.sign_prehash_with_rng(&mut rng(), &prehash).or(invalid())?;
                Ok(sig.as_bytes().to_vec())
            }

            pub fn verify(k: &PublicKey, digest: &[u8], sig: &[u8]) -> bool {
                let Ok(sig) = $c::ecdsa::DerSignature::try_from(sig) else {
                    return false;
                };
                let vk = VerifyingKey::from(k);
                vk.verify_prehash(&fit_digest(digest, $field), &sig).is_ok()
            }

            pub fn ecdh(k: &SecretKey, peer: &PublicKey) -> Vec<u8> {
                let s = $c::ecdh::diffie_hellman(k.to_nonzero_scalar(), peer.as_affine());
                s.raw_secret_bytes().to_vec()
            }
        }
    };
}

ec_curve!(p256m, p256, NistP256, 32);
ec_curve!(p384m, p384, NistP384, 48);
ec_curve!(p521m, p521, NistP521, 66);

/// A parsed PKCS#8 private key.
pub enum Private {
    P256(p256::SecretKey),
    P384(p384::SecretKey),
    P521(p521::SecretKey),
    X25519([u8; 32]),
    Ed25519([u8; 32]),
    Rsa(RsaPrivateKey),
}

/// A parsed PKIX public key.
pub enum Public {
    P256(p256::PublicKey),
    P384(p384::PublicKey),
    P521(p521::PublicKey),
    X25519([u8; 32]),
    Ed25519([u8; 32]),
    Rsa(RsaPublicKey),
}

/// Go's PKCS#8 parser ignores bytes after the first element; keep just that element.
fn first_element(der: &[u8]) -> Option<&[u8]> {
    let (&tag, rest) = der.split_first()?;
    let (&b, rest) = rest.split_first()?;
    let (len, hdr) = if b < 0x80 {
        (usize::from(b), 2)
    } else {
        let n = usize::from(b & 0x7f);
        let bytes = rest.get(..n).filter(|_| (1..=4).contains(&n))?;
        (bytes.iter().fold(0, |a, &x| a << 8 | usize::from(x)), 2 + n)
    };
    (tag == 0x30).then_some(())?;
    der.get(..hdr.checked_add(len)?)
}

pub fn parse_private(der: &[u8]) -> Option<Private> {
    let der = first_element(der)?;
    if let Some(k) = p256m::parse_private(der) {
        return Some(Private::P256(k));
    }
    if let Some(k) = p384m::parse_private(der) {
        return Some(Private::P384(k));
    }
    if let Some(k) = p521m::parse_private(der) {
        return Some(Private::P521(k));
    }
    if let Some(k) = parse_pkcs8_25519(X25519_OID, der) {
        return Some(Private::X25519(k));
    }
    if let Some(k) = parse_pkcs8_25519(ED25519_OID, der) {
        return Some(Private::Ed25519(k));
    }
    // Go validates the key and its precomputed CRT values; a re-encode catches altered values.
    let k = RsaPrivateKey::from_pkcs8_der(der).ok()?;
    k.validate().ok()?;
    (k.to_pkcs8_der().ok()?.as_bytes() == der).then_some(Private::Rsa(k))
}

pub fn parse_public(der: &[u8]) -> Option<Public> {
    if let Some(k) = p256m::parse_public(der) {
        return Some(Public::P256(k));
    }
    if let Some(k) = p384m::parse_public(der) {
        return Some(Public::P384(k));
    }
    if let Some(k) = p521m::parse_public(der) {
        return Some(Public::P521(k));
    }
    if let Some(k) = parse_spki_25519(X25519_OID, der) {
        return Some(Public::X25519(k));
    }
    if let Some(k) = parse_spki_25519(ED25519_OID, der) {
        return Some(Public::Ed25519(k));
    }
    RsaPublicKey::from_public_key_der(der).ok().map(Public::Rsa)
}

fn x25519_public(secret: &[u8; 32]) -> [u8; 32] {
    x25519_dalek::x25519(*secret, x25519_dalek::X25519_BASEPOINT_BYTES)
}

/// `ecdsa_generate`: a new private key as PKCS#8 DER.
pub fn ecdsa_generate(curve: Curve) -> R<Vec<u8>> {
    match curve {
        Curve::P256 => p256m::generate(),
        Curve::P384 => p384m::generate(),
        Curve::P521 => p521m::generate(),
        Curve::X25519 => {
            let mut k = [0u8; 32];
            getrandom::fill(&mut k).or(invalid())?;
            Ok(pkcs8_25519(X25519_OID, &k))
        }
    }
}

/// `public_key_der`: the PKIX public key of a PKCS#8 private key.
pub fn public_key_der(private: &[u8]) -> R<Vec<u8>> {
    match parse_private(private).ok_or(CryptoFail::InvalidInput)? {
        Private::P256(k) => p256m::public_key(&k),
        Private::P384(k) => p384m::public_key(&k),
        Private::P521(k) => p521m::public_key(&k),
        Private::X25519(k) => Ok(spki_25519(X25519_OID, &x25519_public(&k))),
        Private::Ed25519(seed) => {
            let sk = ed25519_dalek::SigningKey::from_bytes(&seed);
            Ok(spki_25519(ED25519_OID, sk.verifying_key().as_bytes()))
        }
        Private::Rsa(k) => k
            .to_public_key()
            .to_public_key_der()
            .map(|d| d.as_bytes().to_vec())
            .or(invalid()),
    }
}

/// `ecdsa_sign`: an ASN.1 DER signature over the digest of `data`.
pub fn ecdsa_sign(private: &[u8], alg: Alg, data: &[u8]) -> R<Vec<u8>> {
    let digest = crate::digest(alg, data);
    match parse_private(private).ok_or(CryptoFail::InvalidInput)? {
        Private::P256(k) => p256m::sign(&k, &digest),
        Private::P384(k) => p384m::sign(&k, &digest),
        Private::P521(k) => p521m::sign(&k, &digest),
        _ => invalid(),
    }
}

/// `ecdsa_verify`; malformed keys or signatures verify as false.
pub fn ecdsa_verify(public: &[u8], alg: Alg, data: &[u8], signature: &[u8]) -> bool {
    let digest = crate::digest(alg, data);
    match parse_public(public) {
        Some(Public::P256(k)) => p256m::verify(&k, &digest, signature),
        Some(Public::P384(k)) => p384m::verify(&k, &digest, signature),
        Some(Public::P521(k)) => p521m::verify(&k, &digest, signature),
        _ => false,
    }
}

/// `ecdh_shared_secret`: the ECDH x-coordinate or X25519 secret; both keys use the same curve.
pub fn ecdh_shared_secret(private: &[u8], peer: &[u8]) -> R<Vec<u8>> {
    let (Some(private), Some(peer)) = (parse_private(private), parse_public(peer)) else {
        return invalid();
    };
    match (private, peer) {
        (Private::P256(k), Public::P256(p)) => Ok(p256m::ecdh(&k, &p)),
        (Private::P384(k), Public::P384(p)) => Ok(p384m::ecdh(&k, &p)),
        (Private::P521(k), Public::P521(p)) => Ok(p521m::ecdh(&k, &p)),
        (Private::X25519(k), Public::X25519(p)) => {
            let s = x25519_dalek::x25519(k, p);
            // A low-order peer point yields an all-zero secret, which Go rejects.
            if s.iter().all(|&b| b == 0) {
                return invalid();
            }
            Ok(s.to_vec())
        }
        _ => invalid(),
    }
}

// ---- RSA ----

/// `rsa_generate`: a new key of `bits` (2048..=8192) as PKCS#8 DER.
pub fn rsa_generate(bits: i64) -> R<Vec<u8>> {
    if !(2048..=8192).contains(&bits) {
        return invalid();
    }
    let k = RsaPrivateKey::new(&mut rng(), bits as usize).or(invalid())?;
    k.to_pkcs8_der()
        .map(|d| d.as_bytes().to_vec())
        .or(invalid())
}

fn rsa_private(der: &[u8]) -> R<RsaPrivateKey> {
    match parse_private(der) {
        Some(Private::Rsa(k)) => Ok(k),
        _ => invalid(),
    }
}

fn rsa_public(der: &[u8]) -> Option<RsaPublicKey> {
    match parse_public(der) {
        Some(Public::Rsa(k)) => Some(k),
        _ => None,
    }
}

/// DigestInfo prefixes of RFC 8017 (and the SHA-3 OIDs of RFC 9688) for PKCS#1 v1.5.
fn digest_info_prefix(alg: Alg) -> &'static [u8] {
    match alg {
        Alg::Md5 => &[
            0x30, 0x20, 0x30, 0x0c, 0x06, 0x08, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x05,
            0x05, 0x00, 0x04, 0x10,
        ],
        Alg::Sha1 => &[
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04,
            0x14,
        ],
        Alg::Sha224 => &[
            0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02,
            0x04, 0x05, 0x00, 0x04, 0x1c,
        ],
        Alg::Sha256 => &[
            0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02,
            0x01, 0x05, 0x00, 0x04, 0x20,
        ],
        Alg::Sha384 => &[
            0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02,
            0x02, 0x05, 0x00, 0x04, 0x30,
        ],
        Alg::Sha512 => &[
            0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02,
            0x03, 0x05, 0x00, 0x04, 0x40,
        ],
        Alg::Sha3_256 => &[
            0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02,
            0x08, 0x05, 0x00, 0x04, 0x20,
        ],
        Alg::Sha3_384 => &[
            0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02,
            0x09, 0x05, 0x00, 0x04, 0x30,
        ],
        Alg::Sha3_512 => &[
            0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02,
            0x0a, 0x05, 0x00, 0x04, 0x40,
        ],
    }
}

fn pkcs1v15_scheme(alg: Alg) -> rsa::pkcs1v15::Pkcs1v15Sign {
    rsa::pkcs1v15::Pkcs1v15Sign {
        hash_len: Some(alg.digest_size()),
        prefix: digest_info_prefix(alg).into(),
    }
}

/// `rsa_sign`: RSASSA-PKCS1-v1_5.
pub fn rsa_sign(private: &[u8], alg: Alg, data: &[u8]) -> R<Vec<u8>> {
    let key = rsa_private(private)?;
    key.sign_with_rng(&mut rng(), pkcs1v15_scheme(alg), &crate::digest(alg, data))
        .or(invalid())
}

/// `rsa_verify`: RSASSA-PKCS1-v1_5.
pub fn rsa_verify(public: &[u8], alg: Alg, data: &[u8], signature: &[u8]) -> bool {
    rsa_public(public).is_some_and(|k| {
        k.verify(pkcs1v15_scheme(alg), &crate::digest(alg, data), signature)
            .is_ok()
    })
}

/// `rsa_sign_pss`: RSASSA-PSS with a digest-sized salt.
pub fn rsa_sign_pss(private: &[u8], alg: Alg, data: &[u8]) -> R<Vec<u8>> {
    let key = rsa_private(private)?;
    let digest = crate::digest(alg, data);
    let salt = alg.digest_size();
    with_digest!(alg, D => key.sign_with_rng(&mut rng(), rsa::pss::Pss::<D>::new_with_salt(salt), &digest))
        .or(invalid())
}

/// `rsa_verify_pss`: RSASSA-PSS with a digest-sized salt.
pub fn rsa_verify_pss(public: &[u8], alg: Alg, data: &[u8], signature: &[u8]) -> bool {
    let Some(key) = rsa_public(public) else {
        return false;
    };
    let digest = crate::digest(alg, data);
    let salt = alg.digest_size();
    with_digest!(alg, D => key.verify(rsa::pss::Pss::<D>::new_with_salt(salt), &digest, signature))
        .is_ok()
}

/// `rsa_encrypt`: RSA-OAEP with an empty label and the given hash for both the label and MGF1.
pub fn rsa_encrypt(public: &[u8], alg: Alg, message: &[u8]) -> R<Vec<u8>> {
    let key = rsa_public(public).ok_or(CryptoFail::InvalidInput)?;
    with_digest!(alg, D => key.encrypt(&mut rng(), rsa::oaep::Oaep::<D>::new(), message))
        .or(invalid())
}

/// `rsa_decrypt`: RSA-OAEP; a rejected ciphertext is an authentication failure.
pub fn rsa_decrypt(private: &[u8], alg: Alg, ciphertext: &[u8]) -> R<Vec<u8>> {
    let key = rsa_private(private)?;
    with_digest!(alg, D => key.decrypt(rsa::oaep::Oaep::<D>::new(), ciphertext))
        .map_err(|_| CryptoFail::AuthenticationFailed)
}
