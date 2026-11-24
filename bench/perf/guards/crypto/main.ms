// Guard: Ed25519 and P-256 sign, verify and key agreement keep their precomputed tables
// (#4178).
import (
	Curve,
	HashAlgorithm,
	ecdh_shared_secret,
	ecdsa_generate,
	ecdsa_sign,
	ecdsa_verify,
	public_key,
	public_key_der,
	sign,
	verify
) from "@std/crypto/crypto.ms"

fn main() Void! {
	seed := "0123456789abcdef0123456789abcdef".to_bytes()
	msg := "hello".to_bytes()
	key := public_key(seed)?
	sig := sign(seed, msg)?
	priv := ecdsa_generate(Curve.P256)?
	pubk := public_key_der(priv)?
	esig := ecdsa_sign(priv, HashAlgorithm.Sha256, msg)?
	var n = 0

	for i in 0..20 {
		if verify(key, msg, sig) { n += 1 }
		n += (sign(seed, msg)?).length()
		if ecdsa_verify(pubk, HashAlgorithm.Sha256, msg, esig) { n += 1 }
		n += (ecdsa_sign(priv, HashAlgorithm.Sha256, msg)?).length() / 100
		n += (ecdh_shared_secret(priv, pubk)?).length()
	}

	print(f"{n}")
}
