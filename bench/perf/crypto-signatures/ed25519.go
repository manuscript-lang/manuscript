// Go port of main.ms: the same 3000 rounds of public_key, sign and verify.
package main

import (
	"crypto/ed25519"
	"fmt"
)

func main() {
	seed := []byte("0123456789abcdef0123456789abcdef")
	msg := []byte("hello")
	sk := ed25519.NewKeyFromSeed(seed)
	key := sk.Public().(ed25519.PublicKey)
	sig := ed25519.Sign(sk, msg)
	n := 0
	for i := 0; i < 3000; i++ {
		if ed25519.Verify(key, msg, sig) {
			n++
		}
		n += len(ed25519.NewKeyFromSeed(seed).Public().(ed25519.PublicKey))
		n += len(ed25519.Sign(sk, msg))
	}
	fmt.Println(n)
}
