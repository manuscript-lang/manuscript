// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"

fn choose(algorithm HashAlgorithm) Void {
	return
}

fn wrong() Void {
	choose("sha256")
}
