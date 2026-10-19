package main

import (
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rsa"
	"crypto/x509"
	"math/big"
	"math/rand"
	"strconv"

	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// deterministicRSA builds a key from seeded primes so that the fixtures use stable key bytes.
func deterministicRSA(seed int64, bits int) *rsa.PrivateKey {
	rng := rand.New(rand.NewSource(seed))
	prime := func() *big.Int {
		for {
			b := make([]byte, bits/16)
			rng.Read(b)
			b[0] |= 0xc0
			b[len(b)-1] |= 1
			p := new(big.Int).SetBytes(b)
			if p.ProbablyPrime(20) {
				return p
			}
		}
	}
	e := big.NewInt(65537)
	for {
		p, q := prime(), prime()
		if p.Cmp(q) == 0 {
			continue
		}
		n := new(big.Int).Mul(p, q)
		if n.BitLen() != bits {
			continue
		}
		p1, q1 := new(big.Int).Sub(p, big.NewInt(1)), new(big.Int).Sub(q, big.NewInt(1))
		phi := new(big.Int).Mul(p1, q1)
		d := new(big.Int).ModInverse(e, phi)
		if d == nil {
			continue
		}
		k := &rsa.PrivateKey{PublicKey: rsa.PublicKey{N: n, E: 65537}, D: d, Primes: []*big.Int{p, q}}
		if err := k.Validate(); err != nil {
			continue
		}
		k.Precompute()
		return k
	}
}

func mustDER(der []byte, err error) []byte {
	if err != nil {
		fatal(err)
	}
	return der
}

// genCryptoAsym records ECDSA, ECDH, X25519 and RSA behavior with deterministic keys. Go's ECDSA,
// PSS and OAEP outputs are randomized, so those rows differ between runs; Rust replays them as
// verification and decryption cases, which hold for any valid output.
func genCryptoAsym(dir string) {
	r := &recorder{}
	rng := rand.New(rand.NewSource(77))
	scalar := func(n int) []byte {
		b := make([]byte, n)
		rng.Read(b)
		b[0] &= 0x7f
		if b[0] == 0 {
			b[0] = 1
		}
		return b
	}
	type key struct {
		name string
		priv []byte
		pub  []byte
	}
	var keys []key
	for _, c := range []struct {
		name  string
		curve elliptic.Curve
		n     int
	}{{"p256", elliptic.P256(), 32}, {"p384", elliptic.P384(), 48}, {"p521", elliptic.P521(), 66}} {
		for i := 0; i < 2; i++ {
			sc := scalar(c.n)
			if c.n == 66 {
				sc[0] &= 1 // the P-521 order has 521 bits
			}
			k, err := ecdsa.ParseRawPrivateKey(c.curve, sc)
			if err != nil {
				fatal(err)
			}
			keys = append(keys, key{c.name + "-" + strconv.Itoa(i), mustDER(x509.MarshalPKCS8PrivateKey(k)), mustDER(x509.MarshalPKIXPublicKey(&k.PublicKey))})
		}
	}
	for i := 0; i < 2; i++ {
		k, err := ecdh.X25519().NewPrivateKey(scalar(32))
		if err != nil {
			fatal(err)
		}
		keys = append(keys, key{"x25519-" + strconv.Itoa(i), mustDER(x509.MarshalPKCS8PrivateKey(k)), mustDER(x509.MarshalPKIXPublicKey(k.PublicKey()))})
	}
	ed := ed25519.NewKeyFromSeed(scalar(32))
	keys = append(keys, key{"ed25519", mustDER(x509.MarshalPKCS8PrivateKey(ed)), mustDER(x509.MarshalPKIXPublicKey(ed.Public()))})
	rsaKeys := []*rsa.PrivateKey{deterministicRSA(5, 2048), deterministicRSA(6, 3072)}
	for i, k := range rsaKeys {
		keys = append(keys, key{"rsa-" + strconv.Itoa(i), mustDER(x509.MarshalPKCS8PrivateKey(k)), mustDER(x509.MarshalPKIXPublicKey(&k.PublicKey))})
	}

	// Malformed and mismatched inputs.
	junk := []key{{"empty", nil, nil}, {"zero", []byte{0}, []byte{0}}, {"seq", []byte{0x30, 0x00}, []byte{0x30, 0x00}}}
	for _, k := range keys {
		if k.name != "p256-0" && k.name != "x25519-0" && k.name != "ed25519" && k.name != "rsa-0" {
			continue
		}
		junk = append(junk, key{"trunc-" + k.name, k.priv[:len(k.priv)/2], k.pub[:len(k.pub)/2]})
		bad := append([]byte(nil), k.priv...)
		bad[len(bad)-1] ^= 1
		badPub := append([]byte(nil), k.pub...)
		badPub[len(badPub)-1] ^= 1
		junk = append(junk, key{"flip-" + k.name, bad, badPub})
		junk = append(junk, key{"trail-" + k.name, append(append([]byte(nil), k.priv...), 0), append(append([]byte(nil), k.pub...), 0)})
	}
	all := append(append([]key(nil), keys...), junk...)
	for _, k := range all {
		r.row("key", k.name, hb(rt.NewBytes(k.priv)), hb(rt.NewBytes(k.pub)))
	}
	byName := map[string]key{}
	for _, k := range all {
		byName[k.name] = k
	}
	B := func(b []byte) *rt.Bytes { return rt.NewBytes(b) }

	data := []*rt.Bytes{B([]byte("hello")), B(scalar(300))}
	for _, k := range all {
		r.row("pub", k.name, "=>", bytesRes(rt.Crypto_PublicKeyDer(nil, B(k.priv))))
	}
	for _, k := range all {
		for ai, alg := range cryptoAlgs {
			a := strconv.Itoa(ai)
			d := data[ai%2]
			sig := rt.Crypto_EcdsaSign(nil, B(k.priv), alg, d)
			r.row("ecsign", k.name, a, hb(d), "=>", b2s(!sig.Failed))
			if sig.Failed {
				continue
			}
			if ai == 3 {
				// Only the matching key accepts.
				for _, v := range all {
					r.row("ecverify", v.name, a, hb(d), hb(sig.Val), "=>", b2s(rt.Crypto_EcdsaVerify(nil, B(v.pub), alg, d, sig.Val)))
				}
			}
			r.row("ecverify", k.name, a, hb(d), hb(sig.Val), "=>", b2s(rt.Crypto_EcdsaVerify(nil, B(k.pub), alg, d, sig.Val)))
			bad := append([]byte(nil), sig.Val.Data...)
			bad[len(bad)/2] ^= 0x40
			r.row("ecverify", k.name, a, hb(d), hb(B(bad)), "=>", b2s(rt.Crypto_EcdsaVerify(nil, B(k.pub), alg, d, B(bad))))
			r.row("ecverify", k.name, a, hb(B([]byte("other"))), hb(sig.Val), "=>", b2s(rt.Crypto_EcdsaVerify(nil, B(k.pub), alg, B([]byte("other")), sig.Val)))
			r.row("ecverify", k.name, a, hb(d), hb(B(sig.Val.Data[:len(sig.Val.Data)-1])), "=>", b2s(rt.Crypto_EcdsaVerify(nil, B(k.pub), alg, d, B(sig.Val.Data[:len(sig.Val.Data)-1]))))
		}
	}
	for _, sig := range []string{"x", "x3000", "x3006020100020100"} {
		r.row("ecverify", "p256-0", "3", hb(data[0]), sig, "=>", "0")
	}
	for _, a := range keys {
		for _, b := range all {
			r.row("ecdh", a.name, b.name, "=>", bytesRes(rt.Crypto_EcdhSharedSecret(nil, B(a.priv), B(b.pub))))
		}
	}
	for _, a := range junk[:6] {
		r.row("ecdh", a.name, "p256-0", "=>", bytesRes(rt.Crypto_EcdhSharedSecret(nil, B(a.priv), B(keys[0].pub))))
	}
	// X25519 low-order public keys.
	for i, pt := range [][]byte{make([]byte, 32), append([]byte{1}, make([]byte, 31)...)} {
		spki := append([]byte{0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00}, pt...)
		r.row("pt", "low"+strconv.Itoa(i), hb(B(spki)))
		for _, k := range keys[6:8] {
			r.row("ecdh", k.name, "low"+strconv.Itoa(i), "=>", bytesRes(rt.Crypto_EcdhSharedSecret(nil, B(k.priv), B(spki))))
		}
	}

	// RSA.
	rsaAlgs := map[string][]int{"rsa-0": {0, 1, 2, 3, 4, 5, 6, 7, 8}, "rsa-1": {3, 5}}
	for _, k := range all {
		priv, pub := B(k.priv), B(k.pub)
		idx, isRSA := rsaAlgs[k.name]
		if !isRSA {
			idx = []int{3}
		}
		for _, ai := range idx {
			alg := cryptoAlgs[ai]
			a := strconv.Itoa(ai)
			d := data[ai%2]
			s := rt.Crypto_RsaSign(nil, priv, alg, d)
			r.row("rsasign", k.name, a, hb(d), "=>", bytesRes(s))
			pss := rt.Crypto_RsaSignPss(nil, priv, alg, d)
			other := (ai + 1) % len(cryptoAlgs)
			if !pss.Failed {
				r.row("pssverify", k.name, a, hb(d), hb(pss.Val), "=>", b2s(rt.Crypto_RsaVerifyPss(nil, pub, alg, d, pss.Val)))
				bad := append([]byte(nil), pss.Val.Data...)
				bad[len(bad)-1] ^= 1
				r.row("pssverify", k.name, a, hb(d), hb(B(bad)), "=>", b2s(rt.Crypto_RsaVerifyPss(nil, pub, alg, d, B(bad))))
				r.row("pssverify", k.name, strconv.Itoa(other), hb(d), hb(pss.Val), "=>", b2s(rt.Crypto_RsaVerifyPss(nil, pub, cryptoAlgs[other], d, pss.Val)))
			}
			if !s.Failed {
				r.row("rsaverify", k.name, a, hb(d), hb(s.Val), "=>", b2s(rt.Crypto_RsaVerify(nil, pub, alg, d, s.Val)))
				bad := append([]byte(nil), s.Val.Data...)
				bad[len(bad)/3] ^= 1
				r.row("rsaverify", k.name, a, hb(d), hb(B(bad)), "=>", b2s(rt.Crypto_RsaVerify(nil, pub, alg, d, B(bad))))
				r.row("rsaverify", k.name, strconv.Itoa(other), hb(d), hb(s.Val), "=>", b2s(rt.Crypto_RsaVerify(nil, pub, cryptoAlgs[other], d, s.Val)))
				r.row("rsaverify", k.name, a, hb(d), hb(B(s.Val.Data[1:])), "=>", b2s(rt.Crypto_RsaVerify(nil, pub, alg, d, B(s.Val.Data[1:]))))
			}
			for _, n := range []int{0, 1, 20, 62, 100, 190, 250} {
				msg := B(scalar(max(n, 1))[:n])
				enc := rt.Crypto_RsaEncrypt(nil, pub, alg, msg)
				r.row("rsaenc", k.name, a, strconv.Itoa(n), "=>", b2s(!enc.Failed))
				if enc.Failed {
					continue
				}
				r.row("rsadec", k.name, a, hb(enc.Val), "=>", bytesRes(rt.Crypto_RsaDecrypt(nil, priv, alg, enc.Val)))
				if n == 20 {
					r.row("rsadec", k.name, strconv.Itoa(other), hb(enc.Val), "=>", bytesRes(rt.Crypto_RsaDecrypt(nil, priv, cryptoAlgs[other], enc.Val)))
					bad := append([]byte(nil), enc.Val.Data...)
					bad[len(bad)/2] ^= 1
					r.row("rsadec", k.name, a, hb(B(bad)), "=>", bytesRes(rt.Crypto_RsaDecrypt(nil, priv, alg, B(bad))))
					r.row("rsadec", k.name, a, hb(B(enc.Val.Data[1:])), "=>", bytesRes(rt.Crypto_RsaDecrypt(nil, priv, alg, B(enc.Val.Data[1:]))))
				}
			}
		}
	}
	for _, bits := range []int{-1, 0, 1, 1024, 2047, 8193, 100000} {
		r.row("rsagen", strconv.Itoa(bits), "=>", bytesRes(rt.Crypto_RsaGenerate(nil, bits)))
	}
	r.write(dir, "crypto_asym.tsv")
}
