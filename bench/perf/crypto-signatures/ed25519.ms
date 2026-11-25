import public_key, sign, verify from "@std/crypto/crypto.ms"

fn main() Void! {
	seed := "0123456789abcdef0123456789abcdef".to_bytes()
	msg := "hello".to_bytes()
	key := public_key(seed)?
	sig := sign(seed, msg)?
	var i = 0
	var n = 0

	while i < 3000 {
		if verify(key, msg, sig) {
			n += 1
		}
		n += (public_key(seed)?).length()
		n += (sign(seed, msg)?).length()
		i += 1
	}

	print(f"{n}")
}
