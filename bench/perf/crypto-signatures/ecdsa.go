// Go port of ecdsa.ms: 1000 rounds of P-256 sign, verify and ECDH on one key.
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"fmt"
)

func main() {
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	h := sha256.Sum256([]byte("hello"))
	sig, _ := ecdsa.SignASN1(rand.Reader, k, h[:])
	ek, _ := k.ECDH()
	n := 0
	for i := 0; i < 1000; i++ {
		s, _ := ecdsa.SignASN1(rand.Reader, k, h[:])
		n += len(s) / 100
		if ecdsa.VerifyASN1(&k.PublicKey, h[:], sig) {
			n++
		}
		secret, _ := ek.ECDH(ek.PublicKey())
		n += len(secret)
	}
	fmt.Println(n)
}
