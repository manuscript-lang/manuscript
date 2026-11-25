// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"

fn choose(algorithm HashAlgorithm) Void {
	return
}

fn wrong() Void {
	choose("sha256")
}
// expect-error: MS3001 10:12 expected HashAlgorithm, found String (in argument 'algorithm' of choose)
