/*
Cryptographic hashes, message authentication, key derivation, encryption and signatures over `Bytes`.
It covers SHA-2 and SHA-3 digests (plus legacy MD5 and SHA-1), HMAC, PBKDF2 and HKDF (`HashAlgorithm`), AES-GCM (`seal` and `open`), AES-CTR and AES-CBC,
Ed25519 (`sign` and `verify`), ECDSA and ECDH on P-256, P-384, P-521 and X25519 (`Curve`), RSA, and constant-time comparison helpers.
Failures such as a wrong key length (EINVAL) or a failed authentication (EAUTH) return an `Error`; the `verify` functions return `false` instead.
For non-cryptographic hashes and CRCs see `@std/crypto/hash.ms`, and for BLAKE2 and ChaCha20-Poly1305 see
`@std/crypto/blake2.ms` and `@std/crypto/chacha20poly1305.ms`.
*/
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	panic from "@std/core.ms",
	ReadStream from "@std/io/io.ms",
	bit_and, bit_not, bit_or, bit_xor, shift_right from "@std/math/math.ms",

	msstd_crypto_aes_cbc_decrypt,
	msstd_crypto_aes_cbc_encrypt,
	msstd_crypto_aes_ctr,
	msstd_crypto_constant_time_equal,
	msstd_crypto_derive_key,
	msstd_crypto_digest,
	msstd_crypto_ecdh_shared_secret,
	msstd_crypto_ecdsa_generate,
	msstd_crypto_ecdsa_sign,
	msstd_crypto_ecdsa_verify,
	msstd_crypto_hasher_finish,
	msstd_crypto_hasher_new,
	msstd_crypto_hasher_update,
	msstd_crypto_hkdf,
	msstd_crypto_hmac,
	msstd_crypto_hmac_hasher_new,
	msstd_crypto_open,
	msstd_crypto_public_key,
	msstd_crypto_public_key_der,
	msstd_crypto_rsa_decrypt,
	msstd_crypto_rsa_encrypt,
	msstd_crypto_rsa_generate,
	msstd_crypto_rsa_sign,
	msstd_crypto_rsa_sign_pss,
	msstd_crypto_rsa_verify,
	msstd_crypto_rsa_verify_pss,
	msstd_crypto_seal,
	msstd_crypto_sign,
	msstd_crypto_verify from "@std/internal/crypto.ms",
)

export extern type NativeHasher

fn NativeHasher.update(data: Bytes) Void:
	msstd_crypto_hasher_update(self, data)

fn NativeHasher.finish() Bytes:
	return msstd_crypto_hasher_finish(self)

// Reports whether two byte strings are equal, without making the comparison time depend
// on their contents. Different lengths are unequal, and the length itself is not
// hidden. Use it to compare secrets such as MACs and tokens instead of `==`.
export fn constant_time_equal(left: Bytes, right: Bytes) Bool:
	return msstd_crypto_constant_time_equal(left, right)

// Returns `left` if `choice` is 1 and `right` if it is 0, without branching on
// `choice`. Any other `choice` faults.
export fn constant_time_select(choice: Int, left: Int, right: Int) Int:
	if choice != 0 and choice != 1:
		panic("crypto: choice must be 0 or 1")

	mask := -choice
	return bit_or(bit_and(mask, left), bit_and(bit_not(mask), right))

// Returns 1 if `left <= right` and 0 otherwise, without branching on the values.
// Both must be in 0 through 2^62 or the result is unspecified.
export fn constant_time_less_or_equal(left: Int, right: Int) Int:
	return 1 + shift_right(right - left, 63)

// Returns the byte-wise exclusive OR of two equal-length byte strings. Strings of
// different lengths return EINVAL.
export fn xor_bytes(left: Bytes, right: Bytes) Bytes!:
	if left.length() != right.length():
		return error(Error("crypto: invalid input", kind: "EINVAL"))

	var out = BytesBuilder()
	for index in 0..left.length():
		out.append(
			bit_xor(
				left.get(index).to_int(),
				right.get(index).to_int(),
			).to_uint8().get_or(0)
		)
	return ok(out.build())

// Derives a key of `length` bytes with PBKDF2-HMAC-SHA-256 and the given iteration
// count. Returns EINVAL for non-positive iterations or a length outside 1 through
// 1048576. `HashAlgorithm.derive_key` accepts other hashes.
export fn derive_key(password: Bytes, salt: Bytes, iterations: Int, length: Int) Bytes!:
	return HashAlgorithm.Sha256.derive_key(password, salt, iterations, length)

// Authenticates and decrypts a value produced by `seal` using AES-GCM with a 16, 24 or
// 32-byte key and the same 12-byte nonce and associated data. A key or nonce of the
// wrong length returns EINVAL. Wrong associated data, an altered or too short
// ciphertext, or the wrong key returns EAUTH.
export fn open(
	key: Bytes,
	nonce: Bytes,
	ciphertext: Bytes,
	associated_data: Bytes,
) Bytes!:
	return msstd_crypto_open(key, nonce, ciphertext, associated_data)

// Derives the Ed25519 public key (32 bytes) for a 32-byte private seed. A seed of any
// other length returns EINVAL.
export fn public_key(seed: Bytes) Bytes!:
	return msstd_crypto_public_key(seed)

// Encrypts and authenticates plaintext with AES-GCM using a 16, 24 or 32-byte key and
// 12-byte nonce, and returns the ciphertext followed by a 16-byte tag. A key or nonce
// of the wrong length returns EINVAL. The caller supplies a nonce that is unique for
// each message under the key.
export fn seal(
	key: Bytes,
	nonce: Bytes,
	plaintext: Bytes,
	associated_data: Bytes,
) Bytes!:
	return msstd_crypto_seal(key, nonce, plaintext, associated_data)

// Returns the SHA-256 digest of the input.
export fn sha256(data: Bytes) Bytes:
	return HashAlgorithm.Sha256.digest(data)

// Returns the SHA-384 digest of the input.
export fn sha384(data: Bytes) Bytes:
	return HashAlgorithm.Sha384.digest(data)

// Returns the SHA-512 digest of the input.
export fn sha512(data: Bytes) Bytes:
	return HashAlgorithm.Sha512.digest(data)

// Signs data with a 32-byte Ed25519 private seed and returns the 64-byte signature. A
// seed of any other length returns EINVAL.
export fn sign(seed: Bytes, data: Bytes) Bytes!:
	return msstd_crypto_sign(seed, data)

// Reports whether `signature` is a valid Ed25519 signature of `data` under the 32-byte
// public key. A malformed key or signature gives `false`.
export fn verify(key: Bytes, data: Bytes, signature: Bytes) Bool:
	return msstd_crypto_verify(key, data, signature)

// Selects an elliptic curve for ECDSA and ECDH keys.
export enum Curve:
	P256  // NIST P-256 (secp256r1).
	P384  // NIST P-384 (secp384r1).
	P521  // NIST P-521 (secp521r1).
	X25519  // Curve25519, valid for key agreement (`ecdh_shared_secret`) only.

// Hashes or authenticates data supplied in chunks. Create one with
// `HashAlgorithm.hasher` or `HashAlgorithm.hmac_hasher`.
export interface Hasher:
	// Appends data to the running hash.
	fn update(data: Bytes) Void
	// Returns the digest of all data supplied since creation or the last `finish`, then
	// resets the state.
	fn finish() move Bytes

/*
Reads `input` to the end and returns its digest under `algorithm`, as `HashAlgorithm.digest` does for bytes in
hand. It keeps no input bytes, and it consumes and closes the stream. A failed read returns its error.
*/
export fn digest(input: ReadStream[Bytes], algorithm: HashAlgorithm) Bytes!:
	var hasher = algorithm.hasher()
	var source = input
	for chunk in source:
		hasher.update(chunk)
	source.close()?
	return ok(hasher.finish())

// Encrypts or decrypts data with AES in CTR mode; the same call does both. `key` is 16,
// 24 or 32 bytes and `iv` is the 16-byte initial counter block. A wrong key or `iv`
// length returns EINVAL. CTR does not authenticate; use `seal` when tampering matters.
export fn aes_ctr(key: Bytes, iv: Bytes, data: Bytes) Bytes!:
	return msstd_crypto_aes_ctr(key, iv, data)

// Encrypts with AES in CBC mode and PKCS#7 padding. `key` is 16, 24 or 32 bytes; `iv`
// is 16 bytes. A wrong key or `iv` length returns EINVAL. CBC does not authenticate;
// use `seal` when tampering matters.
export fn aes_cbc_encrypt(key: Bytes, iv: Bytes, plaintext: Bytes) Bytes!:
	return msstd_crypto_aes_cbc_encrypt(key, iv, plaintext)

// Decrypts AES-CBC data and removes PKCS#7 padding. Returns EINVAL for a bad key or IV
// length or a ciphertext length that is not a positive multiple of 16, and EAUTH for
// invalid padding.
export fn aes_cbc_decrypt(key: Bytes, iv: Bytes, ciphertext: Bytes) Bytes!:
	return msstd_crypto_aes_cbc_decrypt(key, iv, ciphertext)

// Generates a private key on `curve` and returns it as PKCS#8 DER bytes.
export fn ecdsa_generate(curve: Curve) Bytes!:
	return msstd_crypto_ecdsa_generate(curve)

// Returns the PKIX (SubjectPublicKeyInfo) DER public key for a PKCS#8 DER private key.
// Works for ECDSA, X25519, Ed25519 and RSA private keys; other input returns EINVAL.
export fn public_key_der(private_key: Bytes) Bytes!:
	return msstd_crypto_public_key_der(private_key)

// Signs the digest of data with an ECDSA private key (PKCS#8 DER) and returns an ASN.1
// DER signature. A key that is not an ECDSA key, such as an X25519 or RSA key, returns
// EINVAL.
export fn ecdsa_sign(private_key: Bytes, hash: HashAlgorithm, data: Bytes) Bytes!:
	return msstd_crypto_ecdsa_sign(private_key, hash, data)

// Reports whether an ASN.1 DER ECDSA signature is valid for `data` under a PKIX DER
// public key and the same `hash` that signed it. Malformed keys or signatures return
// `false`.
export fn ecdsa_verify(
	public_key: Bytes,
	hash: HashAlgorithm,
	data: Bytes,
	signature: Bytes,
) Bool:
	return msstd_crypto_ecdsa_verify(public_key, hash, data, signature)

// Computes the shared secret between a PKCS#8 DER private key and a PKIX DER public
// key. Both keys must use the same curve (P-256, P-384, P-521 or X25519), or the call
// returns EINVAL.
export fn ecdh_shared_secret(private_key: Bytes, peer_public_key: Bytes) Bytes!:
	return msstd_crypto_ecdh_shared_secret(private_key, peer_public_key)

// Generates an RSA private key of `bits` (2048 through 8192) as PKCS#8 DER bytes. Other
// sizes return EINVAL.
export fn rsa_generate(bits: Int) Bytes!:
	return msstd_crypto_rsa_generate(bits)

// Signs the digest of data with RSASSA-PKCS1-v1_5 using a PKCS#8 DER RSA private key.
// A key that is not an RSA key returns EINVAL.
export fn rsa_sign(private_key: Bytes, hash: HashAlgorithm, data: Bytes) Bytes!:
	return msstd_crypto_rsa_sign(private_key, hash, data)

// Reports whether an RSASSA-PKCS1-v1_5 signature is valid for `data` under a PKIX DER
// RSA public key and the same `hash` that signed it.
export fn rsa_verify(
	public_key: Bytes,
	hash: HashAlgorithm,
	data: Bytes,
	signature: Bytes,
) Bool:
	return msstd_crypto_rsa_verify(public_key, hash, data, signature)

// Signs the digest of data with RSASSA-PSS (salt length equal to the digest size).
export fn rsa_sign_pss(private_key: Bytes, hash: HashAlgorithm, data: Bytes) Bytes!:
	return msstd_crypto_rsa_sign_pss(private_key, hash, data)

// Reports whether an RSASSA-PSS signature produced with a digest-sized salt is valid
// for `data` under a PKIX DER RSA public key.
export fn rsa_verify_pss(
	public_key: Bytes,
	hash: HashAlgorithm,
	data: Bytes,
	signature: Bytes,
) Bool:
	return msstd_crypto_rsa_verify_pss(public_key, hash, data, signature)

// Encrypts a short message with RSA-OAEP using the given hash and a PKIX DER public
// key. A message too long for the key size, or a key that is not an RSA key, returns
// EINVAL.
export fn rsa_encrypt(public_key: Bytes, hash: HashAlgorithm, message: Bytes) Bytes!:
	return msstd_crypto_rsa_encrypt(public_key, hash, message)

// Decrypts an RSA-OAEP message with a PKCS#8 DER private key and the `hash` used to
// encrypt. Returns EAUTH when decryption is rejected, including a wrong `hash` or a
// ciphertext of the wrong length, and EINVAL for a key that is not an RSA key.
export fn rsa_decrypt(private_key: Bytes, hash: HashAlgorithm, ciphertext: Bytes) Bytes!:
	return msstd_crypto_rsa_decrypt(private_key, hash, ciphertext)

// Selects a supported hash algorithm for digests, HMAC, PBKDF2 and HKDF. Md5 and Sha1
// exist for interoperability with existing formats; prefer SHA-2 or SHA-3 for new
// designs.
export enum HashAlgorithm:
	Md5  // MD5, producing a 16-byte digest or HMAC. Not collision resistant.
	Sha1  // SHA-1, producing a 20-byte digest or HMAC. Not collision resistant.
	Sha224  // SHA-224, producing a 28-byte digest or HMAC.
	Sha256  // SHA-256, producing a 32-byte digest or HMAC.
	Sha384  // SHA-384, producing a 48-byte digest or HMAC.
	Sha512  // SHA-512, producing a 64-byte digest or HMAC.
	Sha3_256  // SHA3-256, producing a 32-byte digest or HMAC.
	Sha3_384  // SHA3-384, producing a 48-byte digest or HMAC.
	Sha3_512  // SHA3-512, producing a 64-byte digest or HMAC.

// Returns the digest of `data` as `Bytes` of this algorithm's fixed length. It never
// fails and leaves `data` unchanged.
fn HashAlgorithm.digest(data: Bytes) Bytes:
	return msstd_crypto_digest(self, data)

// Computes HMAC of `data` under `key` with this algorithm. Any key length, including an
// empty key, is accepted.
fn HashAlgorithm.hmac(key: Bytes, data: Bytes) Bytes!:
	return msstd_crypto_hmac(self, key, data)

// Derives a key of `length` bytes with PBKDF2-HMAC using this algorithm and the given
// iteration count. Returns EINVAL for non-positive iterations or a length outside
// 1 through 1048576.
fn HashAlgorithm.derive_key(
	password: Bytes,
	salt: Bytes,
	iterations: Int,
	length: Int,
) Bytes!:
	return msstd_crypto_derive_key(self, password, salt, iterations, length)

/*
Derives `length` bytes from `secret` with HKDF (RFC 5869) using this algorithm.
An empty `salt` uses the algorithm's zero-filled default. Returns EINVAL when
`length` is not positive or exceeds 255 times the digest size.
*/
fn HashAlgorithm.hkdf(secret: Bytes, salt: Bytes, info: Bytes, length: Int) Bytes!:
	return msstd_crypto_hkdf(self, secret, salt, info, length)

// Creates an incremental hasher for this algorithm.
fn HashAlgorithm.hasher() Hasher:
	return msstd_crypto_hasher_new(self)

// Creates an incremental HMAC with this algorithm and `key`; its `finish` returns the
// same bytes as `hmac` over all the data.
fn HashAlgorithm.hmac_hasher(key: Bytes) Hasher:
	return msstd_crypto_hmac_hasher_new(self, key)
