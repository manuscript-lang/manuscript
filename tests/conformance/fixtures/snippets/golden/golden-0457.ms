// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"

fn wrong() Void {
	algorithm := HashAlgorithm.Sha257
}
