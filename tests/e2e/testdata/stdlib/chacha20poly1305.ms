import hex_decode, hex_encode from "@std/data/encoding.ms"
import (
    chacha20,
    chacha20poly1305_open,
    chacha20poly1305_seal,
    poly1305
) from "@std/data/chacha20poly1305.ms"
import CryptoError from "@std/crypto.ms"
import Bytes from "@std/bytes.ms"
import expect_equal, expect_true from "@std/test/test.ms"

fn bytes_of(hex: String) Bytes:
    return hex_decode(hex, none).get(Bytes([]))

let key_hex = "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"
let nonce_hex = "070000004041424344454647"
let aad_hex = "50515253c0c1c2c3c4c5c6c7"
let text = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."

test "Poly1305 matches the RFC 8439 vector":
    let sum = poly1305(
        bytes_of(
            "85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"
        ),
        "Cryptographic Forum Research Group".to_bytes()
    ).get(Bytes([]))
    try expect_equal(hex_encode(sum), "a8061dc1305136c6c22b8baf0c0127a9")

test "ChaCha20-Poly1305 matches the RFC 8439 sealed message":
    let sealed = chacha20poly1305_seal(
        bytes_of(key_hex), bytes_of(nonce_hex), text.to_bytes(), bytes_of(aad_hex)
    ).get(Bytes([]))
    try expect_equal(
        hex_encode(sealed),
        "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691"
    )

    let opened = chacha20poly1305_open(
        bytes_of(key_hex), bytes_of(nonce_hex), sealed, bytes_of(aad_hex)
    ).get(Bytes([]))
    try expect_equal(hex_encode(opened), hex_encode(text.to_bytes()))

test "empty message seals to a bare tag":
    let sealed = chacha20poly1305_seal(
        bytes_of(key_hex), bytes_of(nonce_hex), Bytes([]), Bytes([])
    ).get(Bytes([]))
    try expect_equal(hex_encode(sealed), "a0784d7a4716f3feb4f64e7f4b39bf04")

test "tampering and bad lengths are rejected":
    var sealed = chacha20poly1305_seal(
        bytes_of(key_hex), bytes_of(nonce_hex), text.to_bytes(), bytes_of(aad_hex)
    ).get(Bytes([]))
    try expect_true(
        chacha20poly1305_open(
            bytes_of(key_hex), bytes_of(nonce_hex), sealed, Bytes([])
        ).is_error()
    )
    try expect_true(
        chacha20poly1305_open(
            bytes_of(key_hex), bytes_of(nonce_hex), Bytes([1, 2]), Bytes([])
        ).is_error()
    )
    try expect_true(
        chacha20poly1305_seal(
            Bytes([1]), bytes_of(nonce_hex), Bytes([]), Bytes([])
        ).is_error()
    )
    try expect_true(chacha20(Bytes([1]), bytes_of(nonce_hex), 1, Bytes([])).is_error())
