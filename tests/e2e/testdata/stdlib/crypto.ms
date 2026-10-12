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
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

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

    let mac = value(
        hmac(
            key: "key".to_bytes(),
            data: "The quick brown fox jumps over the lazy dog".to_bytes(),
            algorithm: "sha256"
        )
    )
    if (
        hex_encode(
            mac
        ) != "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
    ): return panic("HMAC vector")

    let derived = value(
        derive_key(
            password: "password".to_bytes(),
            salt: "salt".to_bytes(),
            iterations: 1,
            length: 32
        )
    )
    if (
        hex_encode(
            derived
        ) != "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
    ): return panic("PBKDF2 vector")

test "authenticated encryption detects wrong associated data":
    let key = "01234567890123456789012345678901".to_bytes()
    let nonce = "012345678901".to_bytes()
    let encrypted = value(
        seal(
            key: key,
            nonce: nonce,
            plaintext: "secret".to_bytes(),
            associated_data: "header".to_bytes()
        )
    )
    if (
        value(
            open(
                key: key,
                nonce: nonce,
                ciphertext: encrypted,
                associated_data: "header".to_bytes()
            )
        ) != "secret".to_bytes()
    ): return panic("AES GCM roundtrip")

    let failed: Result[Bytes, CryptoError] = error(
        cause: CryptoError.AuthenticationFailed
    )
    if (
        open(
            key: key,
            nonce: nonce,
            ciphertext: encrypted,
            associated_data: "changed".to_bytes()
        ) != failed
    ): return panic("authentication bypass")

    let invalid: Result[Bytes, CryptoError] = error(cause: CryptoError.InvalidInput)
    if (
        seal(
            key: "short".to_bytes(),
            nonce: nonce,
            plaintext: "".to_bytes(),
            associated_data: "".to_bytes()
        ) != invalid
    ): return panic("invalid key")

test "Ed25519 signatures verify only the signed data":
    let seed = "01234567890123456789012345678901".to_bytes()
    let key = value(public_key(seed))
    let signature = value(
        sign(
            seed: seed,
            data: "message".to_bytes()
        )
    )
    if not verify(
        key: key,
        data: "message".to_bytes(),
        signature: signature
    ): return panic("signature verification")
    if verify(
        key: key,
        data: "changed".to_bytes(),
        signature: signature
    ): return panic("signature forgery")
    if not constant_time_equal(
        left: seed,
        right: seed.clone()
    ): return panic("constant time equality")
    if constant_time_equal(
        left: seed,
        right: "short".to_bytes()
    ): return panic("different lengths")
