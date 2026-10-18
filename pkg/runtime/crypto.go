package msruntime

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/subtle"
	"hash"
)

func cryptoHash(algorithm string) hash.Hash {
	switch algorithm {
	case "sha256":
		return sha256.New()
	case "sha384":
		return sha512.New384()
	case "sha512":
		return sha512.New()
	}
	return nil
}

func cryptoHashName(a HashAlgorithm) string {
	switch a.(type) {
	case HashAlgorithm_Sha256:
		return "sha256"
	case HashAlgorithm_Sha384:
		return "sha384"
	case HashAlgorithm_Sha512:
		return "sha512"
	}
	Raise("invalid HashAlgorithm receiver")
	return ""
}

func cryptoWrite(ctx *Execution, h hash.Hash, data []byte) {
	for len(data) > 0 {
		CheckCancelled(ctx)
		n := min(len(data), 65536)
		h.Write(data[:n])
		data = data[n:]
	}
}

func cryptoDigest(ctx *Execution, algorithm string, data *Bytes) *Bytes {
	h := cryptoHash(algorithm)
	cryptoWrite(ctx, h, dfBytes(data))
	return NewBytes(h.Sum(nil))
}

// Crypto_Sha256 returns the SHA-256 digest of data.
func Crypto_Sha256(ctx *Execution, data *Bytes) *Bytes { return cryptoDigest(ctx, "sha256", data) }

// Crypto_Sha384 returns the SHA-384 digest of data.
func Crypto_Sha384(ctx *Execution, data *Bytes) *Bytes { return cryptoDigest(ctx, "sha384", data) }

// Crypto_Sha512 returns the SHA-512 digest of data.
func Crypto_Sha512(ctx *Execution, data *Bytes) *Bytes { return cryptoDigest(ctx, "sha512", data) }

// HashAlgorithm_Digest hashes data with the selected algorithm.
func HashAlgorithm_Digest(ctx *Execution, algorithm HashAlgorithm, data *Bytes) *Bytes {
	CheckCancelled(ctx)
	return cryptoDigest(ctx, cryptoHashName(algorithm), data)
}

// HashAlgorithm_Hmac computes an HMAC with the selected algorithm.
func HashAlgorithm_Hmac(ctx *Execution, algorithm HashAlgorithm, key, data *Bytes) Result[*Bytes, CryptoError] {
	CheckCancelled(ctx)
	return cryptoHmac(ctx, key, data, cryptoHashName(algorithm))
}

// cryptoHmac computes an HMAC for "sha256", "sha384" or "sha512"; any other
// algorithm is Unsupported.
func cryptoHmac(ctx *Execution, key, data *Bytes, algorithm string) Result[*Bytes, CryptoError] {
	if cryptoHash(algorithm) == nil {
		return Fail[*Bytes, CryptoError](CryptoError_Unsupported{})
	}
	h := hmac.New(func() hash.Hash { return cryptoHash(algorithm) }, dfBytes(key))
	cryptoWrite(ctx, h, dfBytes(data))
	return Ok[*Bytes, CryptoError](NewBytes(h.Sum(nil)))
}

// Crypto_ConstantTimeEqual compares two byte sequences in constant time.
func Crypto_ConstantTimeEqual(_ *Execution, left, right *Bytes) bool {
	return subtle.ConstantTimeCompare(dfBytes(left), dfBytes(right)) == 1
}

// Crypto_DeriveKey derives a key with PBKDF2-HMAC-SHA256.
func Crypto_DeriveKey(ctx *Execution, password, salt *Bytes, iterations, length int) Result[*Bytes, CryptoError] {
	if iterations <= 0 || length <= 0 || length > 1048576 {
		return Fail[*Bytes, CryptoError](CryptoError_InvalidInput{})
	}
	pw, sl := dfBytes(password), dfBytes(salt)
	out := make([]byte, 0, int(length))
	for block := uint32(1); len(out) < length; block++ {
		CheckCancelled(ctx)
		h := hmac.New(sha256.New, pw)
		h.Write(sl)
		h.Write([]byte{byte(block >> 24), byte(block >> 16), byte(block >> 8), byte(block)})
		u := h.Sum(nil)
		t := append([]byte{}, u...)
		for i := 1; i < iterations; i++ {
			if i%256 == 0 {
				CheckCancelled(ctx)
			}
			h.Reset()
			h.Write(u)
			u = h.Sum(u[:0])
			for j := range t {
				t[j] ^= u[j]
			}
		}
		n := min(len(t), length-len(out))
		out = append(out, t[:n]...)
	}
	return Ok[*Bytes, CryptoError](NewBytes(out))
}

func cryptoAEAD(key []byte) (cipher.AEAD, bool) {
	if len(key) != 32 {
		return nil, false
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, false
	}
	g, err := cipher.NewGCM(block)
	return g, err == nil
}

// Crypto_Seal encrypts and authenticates plaintext with AES-256-GCM.
func Crypto_Seal(_ *Execution, key, nonce, plaintext, associatedData *Bytes) Result[*Bytes, CryptoError] {
	g, ok := cryptoAEAD(dfBytes(key))
	n, data := dfBytes(nonce), dfBytes(plaintext)
	if !ok || len(n) != 12 || uint64(len(data)) > ((1<<32)-2)*16 {
		return Fail[*Bytes, CryptoError](CryptoError_InvalidInput{})
	}
	return Ok[*Bytes, CryptoError](NewBytes(g.Seal(nil, n, data, dfBytes(associatedData))))
}

// Crypto_Open authenticates and decrypts AES-256-GCM ciphertext.
func Crypto_Open(_ *Execution, key, nonce, ciphertext, associatedData *Bytes) Result[*Bytes, CryptoError] {
	g, ok := cryptoAEAD(dfBytes(key))
	n := dfBytes(nonce)
	if !ok || len(n) != 12 {
		return Fail[*Bytes, CryptoError](CryptoError_InvalidInput{})
	}
	b, err := g.Open(nil, n, dfBytes(ciphertext), dfBytes(associatedData))
	if err != nil {
		return Fail[*Bytes, CryptoError](CryptoError_AuthenticationFailed{})
	}
	return Ok[*Bytes, CryptoError](NewBytes(b))
}

// Crypto_Sign signs data with the Ed25519 key derived from a 32-byte seed.
func Crypto_Sign(_ *Execution, seed, data *Bytes) Result[*Bytes, CryptoError] {
	s := dfBytes(seed)
	if len(s) != ed25519.SeedSize {
		return Fail[*Bytes, CryptoError](CryptoError_InvalidInput{})
	}
	return Ok[*Bytes, CryptoError](NewBytes(ed25519.Sign(ed25519.NewKeyFromSeed(s), dfBytes(data))))
}

// Crypto_PublicKey returns the Ed25519 public key for a 32-byte seed.
func Crypto_PublicKey(_ *Execution, seed *Bytes) Result[*Bytes, CryptoError] {
	s := dfBytes(seed)
	if len(s) != ed25519.SeedSize {
		return Fail[*Bytes, CryptoError](CryptoError_InvalidInput{})
	}
	key := ed25519.NewKeyFromSeed(s).Public().(ed25519.PublicKey)
	return Ok[*Bytes, CryptoError](NewBytes(append([]byte{}, key...)))
}

// Crypto_Verify reports whether signature signs data under an Ed25519 key.
func Crypto_Verify(_ *Execution, key, data, signature *Bytes) bool {
	k := dfBytes(key)
	if len(k) != ed25519.PublicKeySize {
		return false
	}
	return ed25519.Verify(k, dfBytes(data), dfBytes(signature))
}

// Errors_Message_CryptoError returns a fixed diagnostic that never exposes
// keys, plaintext or ciphertext.
func Errors_Message_CryptoError(_ *Execution, e CryptoError) string {
	switch e.(type) {
	case CryptoError_InvalidInput:
		return dfMessage("cryptography", reasonInvalidInput)
	case CryptoError_Unsupported:
		return dfMessage("cryptography", reasonUnsupported)
	case CryptoError_AuthenticationFailed:
		return dfMessage("cryptography", "authentication failed")
	}
	return dfMessage("cryptography", "operation failed")
}
