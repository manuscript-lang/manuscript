import (
	Curve,
	HashAlgorithm,
	ecdh_shared_secret,
	ecdsa_generate,
	ecdsa_sign,
	ecdsa_verify,
	public_key_der
) from "@std/crypto/crypto.ms"

fn main() Void! {
	priv := ecdsa_generate(Curve.P256)?
	pubk := public_key_der(priv)?
	msg := "hello".to_bytes()
	sig := ecdsa_sign(priv, HashAlgorithm.Sha256, msg)?
	var i = 0
	var n = 0

	while i < 1000 {
		n += (ecdsa_sign(priv, HashAlgorithm.Sha256, msg)?).length() / 100
		if ecdsa_verify(pubk, HashAlgorithm.Sha256, msg, sig) {
			n += 1
		}
		n += (ecdh_shared_secret(priv, pubk)?).length()
		i += 1
	}

	print(f"{n}")
}
