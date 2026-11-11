import (
	Bytes from "@std/bytes.ms",
	HashAlgorithm,
	public_key_der,
	rsa_decrypt,
	rsa_encrypt,
	rsa_generate,
	rsa_sign,
	rsa_sign_pss,
	rsa_verify,
	rsa_verify_pss from "@std/crypto.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

fn widened_sign(key: Bytes) Bytes!:
	return rsa_sign(key, HashAlgorithm.Sha256, "message".to_bytes())

fn widened_decrypt(key: Bytes, data: Bytes) Bytes!:
	return rsa_decrypt(key, HashAlgorithm.Sha256, data)

fn marked(var calls: List[Int], marker: Int, data: Bytes) Bytes:
	calls.append(marker)
	return data

test "RSA PKCS1 PSS and OAEP support every declared hash":
	private := rsa_generate(2048)?
	public := public_key_der(private)?
	data := "payload é🙂".to_bytes()

	for hash in [
		HashAlgorithm.Md5,
		HashAlgorithm.Sha1,
		HashAlgorithm.Sha224,
		HashAlgorithm.Sha256,
		HashAlgorithm.Sha384,
		HashAlgorithm.Sha512,
		HashAlgorithm.Sha3_256,
		HashAlgorithm.Sha3_384,
		HashAlgorithm.Sha3_512,
	]:
		signature := rsa_sign(private, hash, data)?
		expect_true(rsa_verify(public, hash, data, signature))?
		expect_false(rsa_verify(public, hash, "other".to_bytes(), signature))?

		pss := rsa_sign_pss(private, hash, data)?
		expect_true(rsa_verify_pss(public, hash, data, pss))?
		expect_false(rsa_verify_pss(public, hash, "other".to_bytes(), pss))?

		ciphertext := rsa_encrypt(public, hash, data)?
		expect_equal(ciphertext.length(), 256)?
		expect_equal(rsa_decrypt(private, hash, ciphertext)?, data)?
		expect_equal(data, "payload é🙂".to_bytes())?

test "RSA malformed keys and signatures fail without faulting":
	private := rsa_generate(2048)?
	public := public_key_der(private)?
	data := "message".to_bytes()
	bad := "invalid DER".to_bytes()
	signature := rsa_sign(private, HashAlgorithm.Sha256, data)?
	pss := rsa_sign_pss(private, HashAlgorithm.Sha256, data)?

	for bytes in ["".to_bytes(), bad.clone(), private.clone()]:
		expect_false(rsa_verify(bytes, HashAlgorithm.Sha256, data, signature))?
		expect_false(rsa_verify_pss(bytes, HashAlgorithm.Sha256, data, pss))?

	for bytes in ["".to_bytes(), bad.clone(), "truncated".to_bytes()]:
		expect_false(rsa_verify(public, HashAlgorithm.Sha256, data, bytes))?
		expect_false(rsa_verify_pss(public, HashAlgorithm.Sha256, data, bytes))?

	expect_false(rsa_verify(public, HashAlgorithm.Sha384, data, signature))?
	expect_false(rsa_verify_pss(public, HashAlgorithm.Sha384, data, pss))?
	expect_false(rsa_verify(public, HashAlgorithm.Sha256, data, pss))?
	expect_false(rsa_verify_pss(public, HashAlgorithm.Sha256, data, signature))?

	for key in [bad.clone(), public]:
		expect_equal(
			rsa_sign(key, HashAlgorithm.Sha256, data).err(),
			Error("cryptography: invalid input", kind: "EINVAL"),
		)?
		expect_equal(
			rsa_sign_pss(key, HashAlgorithm.Sha256, data).err(),
			Error("cryptography: invalid input", kind: "EINVAL"),
		)?
		expect_equal(
			rsa_decrypt(key, HashAlgorithm.Sha256, data).err(),
			Error("cryptography: invalid input", kind: "EINVAL"),
		)?

	expect_equal(
		rsa_encrypt(bad, HashAlgorithm.Sha256, data).err(),
		Error("cryptography: invalid input", kind: "EINVAL"),
	)?
	expect_equal(
		rsa_generate(1024).err(),
		Error("cryptography: invalid input", kind: "EINVAL"),
	)?
	expect_equal(
		widened_sign(bad).err().message,
		Error("cryptography: invalid input", kind: "EINVAL").message,
	)?
	expect_true(widened_sign(private).is_ok())?

test "RSA OAEP rejects ciphertext and oversized plaintext with domain errors":
	private := rsa_generate(2048)?
	public := public_key_der(private)?
	data := "message".to_bytes()
	ciphertext := rsa_encrypt(public, HashAlgorithm.Sha256, data)?
	for bytes in ["".to_bytes(), "invalid ciphertext".to_bytes()]:
		expect_equal(
			rsa_decrypt(private, HashAlgorithm.Sha256, bytes).err(),
			Error("cryptography: authentication failed", kind: "EAUTH"),
		)?
	expect_equal(
		rsa_decrypt(private, HashAlgorithm.Sha384, ciphertext).err(),
		Error("cryptography: authentication failed", kind: "EAUTH"),
	)?

	oversized := "x".repeat(127)?
	expect_equal(
		rsa_encrypt(public, HashAlgorithm.Sha512, oversized.to_bytes()).err(),
		Error("cryptography: invalid input", kind: "EINVAL"),
	)?

	empty := rsa_encrypt(public, HashAlgorithm.Sha256, "".to_bytes())?
	expect_equal(rsa_decrypt(private, HashAlgorithm.Sha256, empty)?, "".to_bytes())?
	expect_equal(
		widened_decrypt(private, "bad".to_bytes()).err().message,
		Error("cryptography: authentication failed", kind: "EAUTH").message,
	)?
	expect_equal(widened_decrypt(private, ciphertext)?, data)?

test "RSA native function values preserve argument order and borrowed bytes":
	private := rsa_generate(2048)?
	public := public_key_der(private)?
	data := "message".to_bytes()
	sign_message := rsa_sign
	verify_message := rsa_verify
	sign_pss := rsa_sign_pss
	verify_pss := rsa_verify_pss
	encrypt := rsa_encrypt
	decrypt := rsa_decrypt
	var calls: List[Int] = []
	direct := rsa_sign(
		data: marked(var calls, 1, data.clone()),
		hash: HashAlgorithm.Sha256,
		private_key: marked(var calls, 2, private.clone()),
	)?
	expect_equal(calls, [1, 2])?

	signature := sign_message(
		data: marked(var calls, 3, data.clone()),
		hash: HashAlgorithm.Sha256,
		private_key: marked(var calls, 4, private.clone()),
	)?
	expect_equal(calls, [1, 2, 3, 4])?
	expect_equal(signature, direct)?
	expect_true(
		verify_message(
			signature: signature,
			data: data,
			hash: HashAlgorithm.Sha256,
			public_key: public,
		)
	)?

	pss := sign_pss(private, HashAlgorithm.Sha512, data)?
	expect_true(verify_pss(public, HashAlgorithm.Sha512, data, pss))?

	ciphertext := encrypt(public, HashAlgorithm.Sha384, data)?
	expect_equal(decrypt(private, HashAlgorithm.Sha384, ciphertext)?, data)?
	expect_equal(sign_message(private, HashAlgorithm.Sha256, data)?, signature)?
	expect_equal(data, "message".to_bytes())?
