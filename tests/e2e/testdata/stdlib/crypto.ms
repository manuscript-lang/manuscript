import {expect_equal, expect_false} from "@std/testing.ms"
import {
    sha256,
    sha384,
    sha512,
    hmac,
    derive_key,
    seal,
    open,
    public_key,
    sign,
    verify,
    constant_time_equal,
    CryptoError
} from "@std/crypto.ms"
import hex_encode from "@std/encoding.ms"
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
    let mac = try hmac(
        "key".to_bytes(),
        "The quick brown fox jumps over the lazy dog".to_bytes(),
        "sha256"
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
        (try open(key, nonce, encrypted, "header".to_bytes())),
        "secret".to_bytes()
    )
    let failed: Result[Bytes, CryptoError] = error(CryptoError.AuthenticationFailed)
    try expect_equal(open(key, nonce, encrypted, "changed".to_bytes()), failed)
    let invalid: Result[Bytes, CryptoError] = error(CryptoError.InvalidInput)
    try expect_equal(
        seal("short".to_bytes(), nonce, "".to_bytes(), "".to_bytes()),
        invalid
    )

test "Ed25519 signatures verify only the signed data":
    let seed = "01234567890123456789012345678901".to_bytes()
    let key = try public_key(seed)
    let signature = try sign(seed, "message".to_bytes())
    try expect_false(not verify(key, "message".to_bytes(), signature))
    try expect_false(verify(key, "changed".to_bytes(), signature))
    try expect_false(not constant_time_equal(seed, seed.clone()))
    try expect_false(constant_time_equal(seed, "short".to_bytes()))
