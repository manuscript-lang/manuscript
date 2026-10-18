import {expect_false, expect_ok, expect_true} from "@std/testing.ms"
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
    (
        (
            hex_encode(
                sha256("abc".to_bytes())
            ) != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    ) | try expect_false
    (
        (
            sha384("abc".to_bytes()).length() != 48
            or sha512("abc".to_bytes()).length() != 64
        )
    ) | try expect_false
    let mac = (
        hmac(
            key: "key".to_bytes(),
            data: "The quick brown fox jumps over the lazy dog".to_bytes(),
            algorithm: "sha256"
        ) | try expect_ok
    )
    (
        (
            hex_encode(
                mac
            ) != "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        )
    ) | try expect_false
    let derived = (
        derive_key(
            password: "password".to_bytes(),
            salt: "salt".to_bytes(),
            iterations: 1,
            length: 32
        ) | try expect_ok
    )
    (
        (
            hex_encode(
                derived
            ) != "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
        )
    ) | try expect_false

test "authenticated encryption detects wrong associated data":
    let key = "01234567890123456789012345678901".to_bytes()
    let nonce = "012345678901".to_bytes()
    let encrypted = (
        seal(
            key: key,
            nonce: nonce,
            plaintext: "secret".to_bytes(),
            associated_data: "header".to_bytes()
        ) | try expect_ok
    )
    (
        (
            (
                open(
                    key: key,
                    nonce: nonce,
                    ciphertext: encrypted,
                    associated_data: "header".to_bytes()
                ) | try expect_ok
            ) != "secret".to_bytes()
        )
    ) | try expect_false
    let failed: Result[Bytes, CryptoError] = error(CryptoError.AuthenticationFailed)
    (
        (
            open(
                key: key,
                nonce: nonce,
                ciphertext: encrypted,
                associated_data: "changed".to_bytes()
            ) != failed
        )
    ) | try expect_false
    let invalid: Result[Bytes, CryptoError] = error(CryptoError.InvalidInput)
    (
        (
            seal(
                key: "short".to_bytes(),
                nonce: nonce,
                plaintext: "".to_bytes(),
                associated_data: "".to_bytes()
            ) != invalid
        )
    ) | try expect_false

test "Ed25519 signatures verify only the signed data":
    let seed = "01234567890123456789012345678901".to_bytes()
    let key = (public_key(seed) | try expect_ok)
    let signature = (sign(seed: seed, data: "message".to_bytes()) | try expect_ok)
    (verify(key: key, data: "message".to_bytes(), signature: signature)) | try expect_true
    verify(key: key, data: "changed".to_bytes(), signature: signature) | try expect_false
    (constant_time_equal(left: seed, right: seed.clone())) | try expect_true
    constant_time_equal(left: seed, right: "short".to_bytes()) | try expect_false
