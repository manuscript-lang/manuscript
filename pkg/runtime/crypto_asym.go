package msruntime

import (
	"crypto"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"hash"
)

func cryptoInvalid[T any]() Result[T, CryptoError] {
	return Fail[T, CryptoError](CryptoError_InvalidInput{})
}

func cryptoHashID(a HashAlgorithm) crypto.Hash {
	switch a.(type) {
	case HashAlgorithm_Md5:
		return crypto.MD5
	case HashAlgorithm_Sha1:
		return crypto.SHA1
	case HashAlgorithm_Sha224:
		return crypto.SHA224
	case HashAlgorithm_Sha384:
		return crypto.SHA384
	case HashAlgorithm_Sha512:
		return crypto.SHA512
	case HashAlgorithm_Sha3_256:
		return crypto.SHA3_256
	case HashAlgorithm_Sha3_384:
		return crypto.SHA3_384
	case HashAlgorithm_Sha3_512:
		return crypto.SHA3_512
	}
	return crypto.SHA256
}

func cryptoDigestOf(ctx *Execution, a HashAlgorithm, data *Bytes) []byte {
	h := cryptoHash(cryptoHashName(a))
	cryptoWrite(ctx, h, dfBytes(data))
	return h.Sum(nil)
}

func cryptoParsePrivate(der *Bytes) (any, bool) {
	k, err := x509.ParsePKCS8PrivateKey(dfBytes(der))
	return k, err == nil
}

func cryptoParsePublic(der *Bytes) (any, bool) {
	k, err := x509.ParsePKIXPublicKey(dfBytes(der))
	return k, err == nil
}

func cryptoDER(key any, marshal func(any) ([]byte, error)) Result[*Bytes, CryptoError] {
	b, err := marshal(key)
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return Ok[*Bytes, CryptoError](NewBytes(b))
}

func cryptoPKCS8(key any) Result[*Bytes, CryptoError] {
	return cryptoDER(key, x509.MarshalPKCS8PrivateKey)
}

// Crypto_EcdsaGenerate generates a private key and returns it as PKCS#8 DER.
func Crypto_EcdsaGenerate(ctx *Execution, curve Curve) Result[*Bytes, CryptoError] {
	CheckCancelled(ctx)
	switch curve.(type) {
	case Curve_P256:
		return cryptoGenerateEC(elliptic.P256())
	case Curve_P384:
		return cryptoGenerateEC(elliptic.P384())
	case Curve_P521:
		return cryptoGenerateEC(elliptic.P521())
	}
	k, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return cryptoPKCS8(k)
}

func cryptoGenerateEC(c elliptic.Curve) Result[*Bytes, CryptoError] {
	k, err := ecdsa.GenerateKey(c, rand.Reader)
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return cryptoPKCS8(k)
}

// Crypto_PublicKeyDer derives the PKIX DER public key from a PKCS#8 DER private key.
func Crypto_PublicKeyDer(_ *Execution, privateKey *Bytes) Result[*Bytes, CryptoError] {
	k, ok := cryptoParsePrivate(privateKey)
	if !ok {
		return cryptoInvalid[*Bytes]()
	}
	var pub any
	switch k := k.(type) {
	case *rsa.PrivateKey:
		pub = &k.PublicKey
	case *ecdsa.PrivateKey:
		pub = &k.PublicKey
	case ed25519.PrivateKey:
		pub = k.Public()
	case *ecdh.PrivateKey:
		pub = k.PublicKey()
	default:
		return cryptoInvalid[*Bytes]()
	}
	return cryptoDER(pub, x509.MarshalPKIXPublicKey)
}

// Crypto_EcdsaSign signs the digest of data and returns an ASN.1 DER signature.
func Crypto_EcdsaSign(ctx *Execution, privateKey *Bytes, algorithm HashAlgorithm, data *Bytes) Result[*Bytes, CryptoError] {
	k, ok := cryptoParsePrivate(privateKey)
	key, isEC := k.(*ecdsa.PrivateKey)
	if !ok || !isEC {
		return cryptoInvalid[*Bytes]()
	}
	sig, err := ecdsa.SignASN1(rand.Reader, key, cryptoDigestOf(ctx, algorithm, data))
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return Ok[*Bytes, CryptoError](NewBytes(sig))
}

// Crypto_EcdsaVerify verifies an ASN.1 DER ECDSA signature.
func Crypto_EcdsaVerify(ctx *Execution, publicKey *Bytes, algorithm HashAlgorithm, data, signature *Bytes) bool {
	k, ok := cryptoParsePublic(publicKey)
	key, isEC := k.(*ecdsa.PublicKey)
	if !ok || !isEC {
		return false
	}
	return ecdsa.VerifyASN1(key, cryptoDigestOf(ctx, algorithm, data), dfBytes(signature))
}

func cryptoECDHPrivate(k any) (*ecdh.PrivateKey, bool) {
	switch k := k.(type) {
	case *ecdh.PrivateKey:
		return k, true
	case *ecdsa.PrivateKey:
		p, err := k.ECDH()
		return p, err == nil
	}
	return nil, false
}

func cryptoECDHPublic(k any) (*ecdh.PublicKey, bool) {
	switch k := k.(type) {
	case *ecdh.PublicKey:
		return k, true
	case *ecdsa.PublicKey:
		p, err := k.ECDH()
		return p, err == nil
	}
	return nil, false
}

// Crypto_EcdhSharedSecret computes an ECDH or X25519 shared secret.
func Crypto_EcdhSharedSecret(_ *Execution, privateKey, peerPublicKey *Bytes) Result[*Bytes, CryptoError] {
	pk, ok1 := cryptoParsePrivate(privateKey)
	pub, ok2 := cryptoParsePublic(peerPublicKey)
	priv, ok3 := cryptoECDHPrivate(pk)
	peer, ok4 := cryptoECDHPublic(pub)
	if !ok1 || !ok2 || !ok3 || !ok4 {
		return cryptoInvalid[*Bytes]()
	}
	secret, err := priv.ECDH(peer)
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return Ok[*Bytes, CryptoError](NewBytes(secret))
}

// Crypto_RsaGenerate generates an RSA private key as PKCS#8 DER.
func Crypto_RsaGenerate(ctx *Execution, bits int) Result[*Bytes, CryptoError] {
	CheckCancelled(ctx)
	if bits < 2048 || bits > 8192 {
		return cryptoInvalid[*Bytes]()
	}
	k, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return cryptoPKCS8(k)
}

func cryptoRSAPrivate(der *Bytes) (*rsa.PrivateKey, bool) {
	k, ok := cryptoParsePrivate(der)
	key, isRSA := k.(*rsa.PrivateKey)
	return key, ok && isRSA
}

func cryptoRSAPublic(der *Bytes) (*rsa.PublicKey, bool) {
	k, ok := cryptoParsePublic(der)
	key, isRSA := k.(*rsa.PublicKey)
	return key, ok && isRSA
}

// Crypto_RsaSign signs with RSASSA-PKCS1-v1_5.
func Crypto_RsaSign(ctx *Execution, privateKey *Bytes, algorithm HashAlgorithm, data *Bytes) Result[*Bytes, CryptoError] {
	key, ok := cryptoRSAPrivate(privateKey)
	if !ok {
		return cryptoInvalid[*Bytes]()
	}
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, cryptoHashID(algorithm), cryptoDigestOf(ctx, algorithm, data))
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return Ok[*Bytes, CryptoError](NewBytes(sig))
}

// Crypto_RsaVerify verifies an RSASSA-PKCS1-v1_5 signature.
func Crypto_RsaVerify(ctx *Execution, publicKey *Bytes, algorithm HashAlgorithm, data, signature *Bytes) bool {
	key, ok := cryptoRSAPublic(publicKey)
	return ok && rsa.VerifyPKCS1v15(key, cryptoHashID(algorithm), cryptoDigestOf(ctx, algorithm, data), dfBytes(signature)) == nil
}

// Crypto_RsaSignPss signs with RSASSA-PSS and a digest-sized salt.
func Crypto_RsaSignPss(ctx *Execution, privateKey *Bytes, algorithm HashAlgorithm, data *Bytes) Result[*Bytes, CryptoError] {
	key, ok := cryptoRSAPrivate(privateKey)
	if !ok {
		return cryptoInvalid[*Bytes]()
	}
	sig, err := rsa.SignPSS(rand.Reader, key, cryptoHashID(algorithm), cryptoDigestOf(ctx, algorithm, data), &rsa.PSSOptions{SaltLength: rsa.PSSSaltLengthEqualsHash})
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return Ok[*Bytes, CryptoError](NewBytes(sig))
}

// Crypto_RsaVerifyPss verifies an RSASSA-PSS signature.
func Crypto_RsaVerifyPss(ctx *Execution, publicKey *Bytes, algorithm HashAlgorithm, data, signature *Bytes) bool {
	key, ok := cryptoRSAPublic(publicKey)
	return ok && rsa.VerifyPSS(key, cryptoHashID(algorithm), cryptoDigestOf(ctx, algorithm, data), dfBytes(signature), &rsa.PSSOptions{SaltLength: rsa.PSSSaltLengthEqualsHash}) == nil
}

func cryptoOAEPHash(a HashAlgorithm) hash.Hash { return cryptoHash(cryptoHashName(a)) }

// Crypto_RsaEncrypt encrypts a short message with RSA-OAEP.
func Crypto_RsaEncrypt(_ *Execution, publicKey *Bytes, algorithm HashAlgorithm, message *Bytes) Result[*Bytes, CryptoError] {
	key, ok := cryptoRSAPublic(publicKey)
	if !ok {
		return cryptoInvalid[*Bytes]()
	}
	out, err := rsa.EncryptOAEP(cryptoOAEPHash(algorithm), rand.Reader, key, dfBytes(message), nil)
	if err != nil {
		return cryptoInvalid[*Bytes]()
	}
	return Ok[*Bytes, CryptoError](NewBytes(out))
}

// Crypto_RsaDecrypt decrypts an RSA-OAEP message.
func Crypto_RsaDecrypt(_ *Execution, privateKey *Bytes, algorithm HashAlgorithm, ciphertext *Bytes) Result[*Bytes, CryptoError] {
	key, ok := cryptoRSAPrivate(privateKey)
	if !ok {
		return cryptoInvalid[*Bytes]()
	}
	out, err := rsa.DecryptOAEP(cryptoOAEPHash(algorithm), nil, key, dfBytes(ciphertext), nil)
	if err != nil {
		return Fail[*Bytes, CryptoError](CryptoError_AuthenticationFailed{})
	}
	return Ok[*Bytes, CryptoError](NewBytes(out))
}

func cryptoAESBlock(key, iv *Bytes) (cipher.Block, []byte, bool) {
	block, err := aes.NewCipher(dfBytes(key))
	v := dfBytes(iv)
	if err != nil || len(v) != aes.BlockSize {
		return nil, nil, false
	}
	return block, v, true
}

// Crypto_AesCtr applies the AES-CTR keystream; encryption and decryption are identical.
func Crypto_AesCtr(ctx *Execution, key, iv, data *Bytes) Result[*Bytes, CryptoError] {
	block, v, ok := cryptoAESBlock(key, iv)
	if !ok {
		return cryptoInvalid[*Bytes]()
	}
	in := dfBytes(data)
	out := make([]byte, len(in))
	stream := cipher.NewCTR(block, v)
	for off := 0; off < len(in); off += 65536 {
		CheckCancelled(ctx)
		end := min(off+65536, len(in))
		stream.XORKeyStream(out[off:end], in[off:end])
	}
	return Ok[*Bytes, CryptoError](NewBytes(out))
}

// Crypto_AesCbcEncrypt encrypts with AES-CBC and PKCS#7 padding.
func Crypto_AesCbcEncrypt(ctx *Execution, key, iv, plaintext *Bytes) Result[*Bytes, CryptoError] {
	block, v, ok := cryptoAESBlock(key, iv)
	if !ok {
		return cryptoInvalid[*Bytes]()
	}
	CheckCancelled(ctx)
	in := dfBytes(plaintext)
	pad := aes.BlockSize - len(in)%aes.BlockSize
	buf := make([]byte, len(in)+pad)
	copy(buf, in)
	for i := len(in); i < len(buf); i++ {
		buf[i] = byte(pad)
	}
	cipher.NewCBCEncrypter(block, v).CryptBlocks(buf, buf)
	return Ok[*Bytes, CryptoError](NewBytes(buf))
}

// Crypto_AesCbcDecrypt decrypts AES-CBC data and removes PKCS#7 padding.
func Crypto_AesCbcDecrypt(ctx *Execution, key, iv, ciphertext *Bytes) Result[*Bytes, CryptoError] {
	block, v, ok := cryptoAESBlock(key, iv)
	in := dfBytes(ciphertext)
	if !ok || len(in) == 0 || len(in)%aes.BlockSize != 0 {
		return cryptoInvalid[*Bytes]()
	}
	CheckCancelled(ctx)
	buf := make([]byte, len(in))
	cipher.NewCBCDecrypter(block, v).CryptBlocks(buf, in)
	pad := int(buf[len(buf)-1])
	if pad == 0 || pad > aes.BlockSize || pad > len(buf) {
		return Fail[*Bytes, CryptoError](CryptoError_AuthenticationFailed{})
	}
	for _, b := range buf[len(buf)-pad:] {
		if int(b) != pad {
			return Fail[*Bytes, CryptoError](CryptoError_AuthenticationFailed{})
		}
	}
	return Ok[*Bytes, CryptoError](NewBytes(buf[:len(buf)-pad]))
}
