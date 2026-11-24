import (
	Bytes from "@std/bytes.ms",
	Curve, HashAlgorithm, NativeHasher from "@std/crypto/crypto.ms",
)

export extern fn msstd_crypto_constant_time_equal(left, right Bytes) Bool

export extern fn msstd_crypto_verify(key, data, signature Bytes) Bool

export extern fn msstd_crypto_open(
	key,
	nonce,
	ciphertext,
	associated_data Bytes,
) move Bytes!

export extern fn msstd_crypto_public_key(seed Bytes) move Bytes!

export extern fn msstd_crypto_seal(
	key,
	nonce,
	plaintext,
	associated_data Bytes,
) move Bytes!

export extern fn msstd_crypto_sign(seed, data Bytes) move Bytes!

export extern fn msstd_crypto_aes_ctr(key, iv, data Bytes) move Bytes!

export extern fn msstd_crypto_aes_cbc_encrypt(key, iv, plaintext Bytes) move Bytes!

export extern fn msstd_crypto_aes_cbc_decrypt(key, iv, ciphertext Bytes) move Bytes!

export extern fn msstd_crypto_ecdsa_generate(curve Curve) move Bytes!

export extern fn msstd_crypto_public_key_der(private_key Bytes) move Bytes!

export extern fn msstd_crypto_ecdsa_sign(
	private_key Bytes,
	hash HashAlgorithm,
	data Bytes,
) move Bytes!

export extern fn msstd_crypto_ecdsa_verify(
	public_key Bytes,
	hash HashAlgorithm,
	data,
	signature Bytes,
) Bool

export extern fn msstd_crypto_ecdh_shared_secret(
	private_key,
	peer_public_key Bytes,
) move Bytes!

export extern fn msstd_crypto_rsa_generate(bits Int) move Bytes!

export extern fn msstd_crypto_rsa_sign(
	private_key Bytes,
	hash HashAlgorithm,
	data Bytes,
) move Bytes!

export extern fn msstd_crypto_rsa_verify(
	public_key Bytes,
	hash HashAlgorithm,
	data,
	signature Bytes,
) Bool

export extern fn msstd_crypto_rsa_sign_pss(
	private_key Bytes,
	hash HashAlgorithm,
	data Bytes,
) move Bytes!

export extern fn msstd_crypto_rsa_verify_pss(
	public_key Bytes,
	hash HashAlgorithm,
	data,
	signature Bytes,
) Bool

export extern fn msstd_crypto_rsa_encrypt(
	public_key Bytes,
	hash HashAlgorithm,
	message Bytes,
) move Bytes!

export extern fn msstd_crypto_rsa_decrypt(
	private_key Bytes,
	hash HashAlgorithm,
	ciphertext Bytes,
) move Bytes!

export extern fn msstd_crypto_digest(value HashAlgorithm, data Bytes) move Bytes

export extern fn msstd_crypto_hmac(value HashAlgorithm, key, data Bytes) move Bytes!

export extern fn msstd_crypto_derive_key(
	value HashAlgorithm,
	password,
	salt Bytes,
	iterations,
	length Int,
) move Bytes!

export extern fn msstd_crypto_hkdf(
	value HashAlgorithm,
	secret,
	salt,
	info Bytes,
	length Int,
) move Bytes!

export extern fn msstd_crypto_hasher_new(alg HashAlgorithm) move NativeHasher

export extern fn msstd_crypto_hmac_hasher_new(
	alg HashAlgorithm,
	key Bytes,
) move NativeHasher

export extern fn msstd_crypto_hasher_update(hasher NativeHasher, data Bytes) Void

export extern fn msstd_crypto_hasher_finish(hasher NativeHasher) move Bytes
