# conform: tags=stdlib-crypto,stdlib-testing,testing,tier-stdlib,try-result,functions,alternatives
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/crypto-rsa.ms
import {
    CryptoError,
    HashAlgorithm,
    public_key_der,
    rsa_generate,
    rsa_sign,
    rsa_verify,
    rsa_sign_pss,
    rsa_verify_pss,
    rsa_encrypt,
    rsa_decrypt
} from "@std/crypto.ms"
import Bytes from "@std/bytes.ms"
import {expect_equal, expect_true, expect_false} from "@std/testing.ms"

fn widened_sign(key: Bytes) Result[Bytes, Error]:
    return rsa_sign(key, HashAlgorithm.Sha256, "message".to_bytes())

fn widened_decrypt(key: Bytes, data: Bytes) Result[Bytes, Error]:
    return rsa_decrypt(key, HashAlgorithm.Sha256, data)

fn marked(var calls: List[Int], marker: Int, data: Bytes) Bytes:
    calls.append(marker)
    return data

test "RSA PKCS1 PSS and OAEP support every declared hash":
    let private = try rsa_generate(2048)
    let public = try public_key_der(private)
    let data = "payload é🙂".to_bytes()

    for hash in [
        HashAlgorithm.Md5,
        HashAlgorithm.Sha1,
        HashAlgorithm.Sha224,
        HashAlgorithm.Sha256,
        HashAlgorithm.Sha384,
        HashAlgorithm.Sha512,
        HashAlgorithm.Sha3_256,
        HashAlgorithm.Sha3_384,
        HashAlgorithm.Sha3_512
    ]:
        let signature = try rsa_sign(private, hash, data)
        try expect_true(rsa_verify(public, hash, data, signature))
        try expect_false(rsa_verify(public, hash, "other".to_bytes(), signature))
        let pss = try rsa_sign_pss(private, hash, data)
        try expect_true(rsa_verify_pss(public, hash, data, pss))
        try expect_false(rsa_verify_pss(public, hash, "other".to_bytes(), pss))
        let ciphertext = try rsa_encrypt(public, hash, data)
        try expect_equal(ciphertext.length(), 256)
        try expect_equal(try rsa_decrypt(private, hash, ciphertext), data)
        try expect_equal(data, "payload é🙂".to_bytes())

test "RSA malformed keys and signatures fail without faulting":
    let private = try rsa_generate(2048)
    let public = try public_key_der(private)
    let data = "message".to_bytes()
    let bad = "invalid DER".to_bytes()
    let signature = try rsa_sign(private, HashAlgorithm.Sha256, data)
    let pss = try rsa_sign_pss(private, HashAlgorithm.Sha256, data)

    for bytes in ["".to_bytes(), bad.clone(), private.clone()]:
        try expect_false(rsa_verify(bytes, HashAlgorithm.Sha256, data, signature))
        try expect_false(rsa_verify_pss(bytes, HashAlgorithm.Sha256, data, pss))

    for bytes in ["".to_bytes(), bad.clone(), "truncated".to_bytes()]:
        try expect_false(rsa_verify(public, HashAlgorithm.Sha256, data, bytes))
        try expect_false(rsa_verify_pss(public, HashAlgorithm.Sha256, data, bytes))

    try expect_false(rsa_verify(public, HashAlgorithm.Sha384, data, signature))
    try expect_false(rsa_verify_pss(public, HashAlgorithm.Sha384, data, pss))
    try expect_false(rsa_verify(public, HashAlgorithm.Sha256, data, pss))
    try expect_false(rsa_verify_pss(public, HashAlgorithm.Sha256, data, signature))

    for key in [bad.clone(), public]:
        try expect_equal(
            rsa_sign(key, HashAlgorithm.Sha256, data).err(),
            CryptoError.InvalidInput
        )
        try expect_equal(
            rsa_sign_pss(key, HashAlgorithm.Sha256, data).err(),
            CryptoError.InvalidInput
        )
        try expect_equal(
            rsa_decrypt(key, HashAlgorithm.Sha256, data).err(),
            CryptoError.InvalidInput
        )

    try expect_equal(
        rsa_encrypt(bad, HashAlgorithm.Sha256, data).err(),
        CryptoError.InvalidInput
    )
    try expect_equal(rsa_generate(1024).err(), CryptoError.InvalidInput)
    try expect_equal(
        widened_sign(bad).err().message(),
        CryptoError.InvalidInput.message()
    )
    try expect_true(widened_sign(private).is_ok())

test "RSA OAEP rejects ciphertext and oversized plaintext with domain errors":
    let private = try rsa_generate(2048)
    let public = try public_key_der(private)
    let data = "message".to_bytes()
    let ciphertext = try rsa_encrypt(public, HashAlgorithm.Sha256, data)
    for bytes in ["".to_bytes(), "invalid ciphertext".to_bytes()]:
        try expect_equal(
            rsa_decrypt(private, HashAlgorithm.Sha256, bytes).err(),
            CryptoError.AuthenticationFailed
        )
    try expect_equal(
        rsa_decrypt(private, HashAlgorithm.Sha384, ciphertext).err(),
        CryptoError.AuthenticationFailed
    )
    let oversized = try "x".repeat(127)
    try expect_equal(
        rsa_encrypt(public, HashAlgorithm.Sha512, oversized.to_bytes()).err(),
        CryptoError.InvalidInput
    )
    let empty = try rsa_encrypt(public, HashAlgorithm.Sha256, "".to_bytes())
    try expect_equal(
        try rsa_decrypt(private, HashAlgorithm.Sha256, empty),
        "".to_bytes()
    )
    try expect_equal(
        widened_decrypt(private, "bad".to_bytes()).err().message(),
        CryptoError.AuthenticationFailed.message()
    )
    try expect_equal(try widened_decrypt(private, ciphertext), data)

test "RSA native function values preserve argument order and borrowed bytes":
    let private = try rsa_generate(2048)
    let public = try public_key_der(private)
    let data = "message".to_bytes()
    let sign_message = rsa_sign
    let verify_message = rsa_verify
    let sign_pss = rsa_sign_pss
    let verify_pss = rsa_verify_pss
    let encrypt = rsa_encrypt
    let decrypt = rsa_decrypt
    var calls: List[Int] = []
    let direct = try rsa_sign(
        data: marked(var calls, 1, data.clone()),
        hash: HashAlgorithm.Sha256,
        private_key: marked(var calls, 2, private.clone())
    )
    try expect_equal(calls, [1, 2])
    let signature = try sign_message(
        data: marked(var calls, 3, data.clone()),
        hash: HashAlgorithm.Sha256,
        private_key: marked(var calls, 4, private.clone())
    )
    try expect_equal(calls, [1, 2, 3, 4])
    try expect_equal(signature, direct)
    try expect_true(
        verify_message(
            signature: signature,
            data: data,
            hash: HashAlgorithm.Sha256,
            public_key: public
        )
    )
    let pss = try sign_pss(private, HashAlgorithm.Sha512, data)
    try expect_true(verify_pss(public, HashAlgorithm.Sha512, data, pss))
    let ciphertext = try encrypt(public, HashAlgorithm.Sha384, data)
    try expect_equal(try decrypt(private, HashAlgorithm.Sha384, ciphertext), data)
    try expect_equal(try sign_message(private, HashAlgorithm.Sha256, data), signature)
    try expect_equal(data, "message".to_bytes())
