import {
    sha256,
    sha384,
    sha512,
    derive_key,
    seal,
    open,
    public_key,
    sign,
    verify,
    constant_time_equal,
    aes_ctr,
    aes_cbc_encrypt,
    aes_cbc_decrypt,
    ecdsa_generate,
    ecdsa_sign,
    ecdsa_verify,
    ecdh_shared_secret,
    public_key_der,
    rsa_generate,
    rsa_sign,
    rsa_verify,
    rsa_sign_pss,
    rsa_verify_pss,
    rsa_encrypt,
    rsa_decrypt,
    Curve,
    CryptoError,
    HashAlgorithm
} from "@std/crypto.ms"
import {hex_encode, hex_decode} from "@std/encoding.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"

test "crypto known SHA256 HMAC and PBKDF2 vectors":
    if (
        hex_encode(
            sha256("abc".to_bytes())
        ) != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    ): return panic("SHA256 vector")
    if (
        sha384("abc".to_bytes()).length() != 48
        or sha512("abc".to_bytes()).length() != 64
    ): return panic("digest sizes")

    let mac = (
        try HashAlgorithm
        .Sha256
        .hmac(
            "key".to_bytes(),
            "The quick brown fox jumps over the lazy dog".to_bytes()
        )
    )
    if (
        hex_encode(
            mac
        ) != "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
    ): return panic("HMAC vector")

    let derived = try derive_key("password".to_bytes(), "salt".to_bytes(), 1, 32)
    if (
        hex_encode(
            derived
        ) != "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
    ): return panic("PBKDF2 vector")

test "additional hash algorithms match published vectors":
    let abc = "abc".to_bytes()
    if hex_encode(HashAlgorithm.Md5.digest(abc)) != "900150983cd24fb0d6963f7d28e17f72": return panic(
        "MD5 vector"
    )
    if (
        hex_encode(
            HashAlgorithm.Sha1.digest(abc)
        ) != "a9993e364706816aba3e25717850c26c9cd0d89d"
    ): return panic("SHA1 vector")
    if (
        hex_encode(
            HashAlgorithm.Sha224.digest(abc)
        ) != "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"
    ): return panic("SHA224 vector")
    if (
        hex_encode(
            HashAlgorithm.Sha3_256.digest(abc)
        ) != "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"
    ): return panic("SHA3-256 vector")
    if (
        HashAlgorithm.Sha3_384.digest(abc).length() != 48
        or HashAlgorithm.Sha3_512.digest(abc).length() != 64
    ): return panic("SHA3 sizes")

test "key derivation supports PBKDF2 and HKDF across hashes":
    let pbkdf2 = (
        try HashAlgorithm
        .Sha1
        .derive_key("password".to_bytes(), "salt".to_bytes(), 1, 20)
    )
    if hex_encode(pbkdf2) != "0c60c80f961f0e71f3a9b524af6012062fe037a6": return panic(
        "PBKDF2-SHA1 vector"
    )

    let secret = try hex_decode("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
    let salt = try hex_decode("000102030405060708090a0b0c")
    let info = try hex_decode("f0f1f2f3f4f5f6f7f8f9")
    let okm = try HashAlgorithm.Sha256.hkdf(secret, salt, info, 42)
    if (
        hex_encode(
            okm
        ) != "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
    ): return panic("HKDF vector")

    let invalid: Result[Bytes, CryptoError] = error(CryptoError.InvalidInput)
    if HashAlgorithm.Sha256.hkdf(secret, salt, info, 255 * 32 + 1) != invalid: return panic(
        "HKDF length bound"
    )
    if HashAlgorithm.Sha256.derive_key(secret, salt, 0, 16) != invalid: return panic(
        "PBKDF2 iterations bound"
    )

test "AES-GCM accepts 128 and 192 bit keys":
    let nonce = "012345678901".to_bytes()

    for size in [16, 24]:
        let key = try "0123456789012345678901234567890123".to_bytes().slice(0, size)
        let boxed = try seal(key, nonce, "secret".to_bytes(), "".to_bytes())
        if (try open(key, nonce, boxed, "".to_bytes())) != "secret".to_bytes(): return panic(
            "AES key size"
        )

test "authenticated encryption detects wrong associated data":
    let key = "01234567890123456789012345678901".to_bytes()
    let nonce = "012345678901".to_bytes()
    let encrypted = try seal(key, nonce, "secret".to_bytes(), "header".to_bytes())
    if ((try open(key, nonce, encrypted, "header".to_bytes())) != "secret".to_bytes()): return panic(
        "AES GCM roundtrip"
    )

    let failed: Result[Bytes, CryptoError] = error(CryptoError.AuthenticationFailed)
    if (open(key, nonce, encrypted, "changed".to_bytes()) != failed): return panic(
        "authentication bypass"
    )

    let invalid: Result[Bytes, CryptoError] = error(CryptoError.InvalidInput)
    if (seal("short".to_bytes(), nonce, "".to_bytes(), "".to_bytes()) != invalid): return panic(
        "invalid key"
    )

test "Ed25519 signatures verify only the signed data":
    let seed = "01234567890123456789012345678901".to_bytes()
    let key = try public_key(seed)
    let signature = try sign(seed, "message".to_bytes())
    if not verify(key, "message".to_bytes(), signature): return panic(
        "signature verification"
    )
    if verify(key, "changed".to_bytes(), signature): return panic("signature forgery")
    if not constant_time_equal(seed, seed.clone()): return panic(
        "constant time equality"
    )
    if constant_time_equal(seed, "short".to_bytes()): return panic("different lengths")

test "incremental hashers match one-shot digests":
    let hasher = HashAlgorithm.Sha256.hasher()
    hasher.update("a".to_bytes())
    hasher.update("bc".to_bytes())
    if hasher.finish() != sha256("abc".to_bytes()): return panic("incremental sha256")

    hasher.update("abc".to_bytes())
    if hasher.finish() != sha256("abc".to_bytes()): return panic("hasher reset")

    let mac = HashAlgorithm.Sha256.hmac_hasher("key".to_bytes())
    mac.update("The quick brown fox jumps over the lazy dog".to_bytes())
    if (
        hex_encode(
            mac.finish()
        ) != "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
    ): return panic("incremental hmac")

test "AES CTR and CBC round trip":
    let key = "0123456789012345".to_bytes()
    let iv = "abcdefghijklmnop".to_bytes()
    let message = "attack at dawn, attack at dawn".to_bytes()
    let stream = try aes_ctr(key, iv, message)
    if (try aes_ctr(key, iv, stream)) != message: return panic("CTR roundtrip")

    let boxed = try aes_cbc_encrypt(key, iv, message)
    if boxed.length() != 32: return panic("CBC padding")
    if (try aes_cbc_decrypt(key, iv, boxed)) != message: return panic("CBC roundtrip")

    let bad: Result[Bytes, CryptoError] = error(CryptoError.InvalidInput)
    if aes_cbc_decrypt(key, "short".to_bytes(), boxed) != bad: return panic("CBC iv")

test "ECDSA signs and ECDH agrees":
    let private = try ecdsa_generate(Curve.P256)
    let public = try public_key_der(private)
    let signature = try ecdsa_sign(private, HashAlgorithm.Sha256, "m".to_bytes())
    if not ecdsa_verify(public, HashAlgorithm.Sha256, "m".to_bytes(), signature): return panic(
        "ECDSA verify"
    )
    if ecdsa_verify(public, HashAlgorithm.Sha256, "x".to_bytes(), signature): return panic(
        "ECDSA forgery"
    )

    for curve in [Curve.P256, Curve.P384, Curve.X25519]:
        let a = try ecdsa_generate(curve)
        let b = try ecdsa_generate(curve)
        let left = try ecdh_shared_secret(a, try public_key_der(b))
        let right = try ecdh_shared_secret(b, try public_key_der(a))
        if left != right: return panic("ECDH mismatch")

test "RSA signs and encrypts":
    let private = try rsa_generate(2048)
    let public = try public_key_der(private)
    let data = "payload".to_bytes()
    let signature = try rsa_sign(private, HashAlgorithm.Sha256, data)
    if not rsa_verify(public, HashAlgorithm.Sha256, data, signature): return panic(
        "RSA verify"
    )
    if rsa_verify(public, HashAlgorithm.Sha256, "other".to_bytes(), signature): return panic(
        "RSA forgery"
    )

    let pss = try rsa_sign_pss(private, HashAlgorithm.Sha256, data)
    if not rsa_verify_pss(public, HashAlgorithm.Sha256, data, pss): return panic(
        "PSS verify"
    )

    let sealed = try rsa_encrypt(public, HashAlgorithm.Sha256, data)
    if (try rsa_decrypt(private, HashAlgorithm.Sha256, sealed)) != data: return panic(
        "OAEP roundtrip"
    )
