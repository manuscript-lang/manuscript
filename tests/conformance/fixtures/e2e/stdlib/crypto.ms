# conform: tags=aliasing,control-flow,match,modules,stdlib-bytes,stdlib-crypto,stdlib-encoding,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/crypto.ms
import expect_equal, expect_false, expect_true from "@std/test/test.ms"
import (
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
    HashAlgorithm
) from "@std/crypto.ms"
import hex_encode, hex_decode from "@std/data/encoding.ms"
import Bytes from "@std/bytes.ms"

test "crypto known SHA256 HMAC and PBKDF2 vectors":
    try expect_false(
        (
            hex_encode(
                sha256("abc".to_bytes())
            ) != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    )
    try expect_false(
        (
            sha384("abc".to_bytes()).length() != 48
            or sha512("abc".to_bytes()).length() != 64
        )
    )

    let mac = try HashAlgorithm.Sha256.hmac(
        "key".to_bytes(), "The quick brown fox jumps over the lazy dog".to_bytes()
    )
    try expect_false(
        (
            hex_encode(
                mac
            ) != "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        )
    )

    let derived = try derive_key("password".to_bytes(), "salt".to_bytes(), 1, 32)
    try expect_false(
        (
            hex_encode(
                derived
            ) != "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
        )
    )

test "authenticated encryption detects wrong associated data":
    let key = "01234567890123456789012345678901".to_bytes()
    let nonce = "012345678901".to_bytes()
    let encrypted = try seal(key, nonce, "secret".to_bytes(), "header".to_bytes())
    try expect_equal(
        (try open(key, nonce, encrypted, "header".to_bytes())), "secret".to_bytes()
    )

    let failed: Bytes! = error(Error("cryptography: authentication failed", kind: ErrorCategory.Other))
    try expect_equal(open(key, nonce, encrypted, "changed".to_bytes()), failed)

    let invalid: Bytes! = error(Error("cryptography: invalid input", kind: ErrorCategory.InvalidInput))
    try expect_equal(
        seal("short".to_bytes(), nonce, "".to_bytes(), "".to_bytes()), invalid
    )

test "Ed25519 signatures verify only the signed data":
    let seed = "01234567890123456789012345678901".to_bytes()
    let key = try public_key(seed)
    let signature = try sign(seed, "message".to_bytes())
    try expect_false(not verify(key, "message".to_bytes(), signature))
    try expect_false(verify(key, "changed".to_bytes(), signature))
    try expect_false(not constant_time_equal(seed, seed.clone()))
    try expect_false(constant_time_equal(seed, "short".to_bytes()))

test "additional hash algorithms match published vectors":
    let abc = "abc".to_bytes()
    try expect_equal(
        hex_encode(HashAlgorithm.Md5.digest(abc)), "900150983cd24fb0d6963f7d28e17f72"
    )
    try expect_equal(
        hex_encode(HashAlgorithm.Sha1.digest(abc)),
        "a9993e364706816aba3e25717850c26c9cd0d89d"
    )
    try expect_equal(
        hex_encode(HashAlgorithm.Sha224.digest(abc)),
        "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"
    )
    try expect_equal(
        hex_encode(HashAlgorithm.Sha3_256.digest(abc)),
        "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"
    )
    try expect_equal(HashAlgorithm.Sha3_384.digest(abc).length(), 48)
    try expect_equal(HashAlgorithm.Sha3_512.digest(abc).length(), 64)

test "key derivation supports PBKDF2 and HKDF across hashes":
    let pbkdf2 = try HashAlgorithm.Sha1.derive_key(
        "password".to_bytes(), "salt".to_bytes(), 1, 20
    )
    try expect_equal(hex_encode(pbkdf2), "0c60c80f961f0e71f3a9b524af6012062fe037a6")

    let secret = try hex_decode("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
    let salt = try hex_decode("000102030405060708090a0b0c")
    let info = try hex_decode("f0f1f2f3f4f5f6f7f8f9")
    let okm = try HashAlgorithm.Sha256.hkdf(secret, salt, info, 42)
    try expect_equal(
        hex_encode(okm),
        "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
    )

    let invalid: Bytes! = error(Error("cryptography: invalid input", kind: ErrorCategory.InvalidInput))
    try expect_equal(
        HashAlgorithm.Sha256.hkdf(secret, salt, info, 255 * 32 + 1), invalid
    )
    try expect_equal(HashAlgorithm.Sha256.derive_key(secret, salt, 0, 16), invalid)

test "AES-GCM accepts 128 and 192 bit keys":
    let nonce = "012345678901".to_bytes()

    for size in [16, 24]:
        let key = try "0123456789012345678901234567890123".to_bytes().slice(0, size)
        let boxed = try seal(key, nonce, "secret".to_bytes(), "".to_bytes())
        try expect_equal(
            try open(key, nonce, boxed, "".to_bytes()), "secret".to_bytes()
        )

test "incremental hashers match one-shot digests":
    let hasher = HashAlgorithm.Sha256.hasher()
    hasher.update("a".to_bytes())
    hasher.update("bc".to_bytes())
    try expect_equal(hasher.finish(), sha256("abc".to_bytes()))
    hasher.update("abc".to_bytes())
    try expect_equal(hasher.finish(), sha256("abc".to_bytes()))

    let mac = HashAlgorithm.Sha256.hmac_hasher("key".to_bytes())
    mac.update("The quick brown fox jumps over the lazy dog".to_bytes())
    try expect_equal(
        hex_encode(mac.finish()),
        "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
    )

test "AES CTR and CBC round trip":
    let key = "0123456789012345".to_bytes()
    let iv = "abcdefghijklmnop".to_bytes()
    let message = "attack at dawn, attack at dawn".to_bytes()
    let stream = try aes_ctr(key, iv, message)
    try expect_equal(try aes_ctr(key, iv, stream), message)

    let boxed = try aes_cbc_encrypt(key, iv, message)
    try expect_equal(boxed.length(), 32)
    try expect_equal(try aes_cbc_decrypt(key, iv, boxed), message)

    let bad: Bytes! = error(Error("cryptography: invalid input", kind: ErrorCategory.InvalidInput))
    try expect_equal(aes_cbc_decrypt(key, "short".to_bytes(), boxed), bad)

test "ECDSA signs and ECDH agrees":
    let private = try ecdsa_generate(Curve.P256)
    let public = try public_key_der(private)
    let signature = try ecdsa_sign(private, HashAlgorithm.Sha256, "m".to_bytes())
    try expect_true(
        ecdsa_verify(public, HashAlgorithm.Sha256, "m".to_bytes(), signature)
    )
    try expect_false(
        ecdsa_verify(public, HashAlgorithm.Sha256, "x".to_bytes(), signature)
    )

    for curve in [Curve.P256, Curve.P384, Curve.X25519]:
        let a = try ecdsa_generate(curve)
        let b = try ecdsa_generate(curve)
        let left = try ecdh_shared_secret(a, try public_key_der(b))
        let right = try ecdh_shared_secret(b, try public_key_der(a))
        try expect_equal(left, right)

test "RSA signs and encrypts":
    let private = try rsa_generate(2048)
    let public = try public_key_der(private)
    let data = "payload".to_bytes()
    let signature = try rsa_sign(private, HashAlgorithm.Sha256, data)
    try expect_true(rsa_verify(public, HashAlgorithm.Sha256, data, signature))
    try expect_false(
        rsa_verify(public, HashAlgorithm.Sha256, "other".to_bytes(), signature)
    )

    let pss = try rsa_sign_pss(private, HashAlgorithm.Sha256, data)
    try expect_true(rsa_verify_pss(public, HashAlgorithm.Sha256, data, pss))

    let sealed = try rsa_encrypt(public, HashAlgorithm.Sha256, data)
    try expect_equal(try rsa_decrypt(private, HashAlgorithm.Sha256, sealed), data)
