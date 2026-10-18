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
    CryptoError,
    HashAlgorithm
} from "@std/crypto.ms"
import hex_encode from "@std/encoding.ms"
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
