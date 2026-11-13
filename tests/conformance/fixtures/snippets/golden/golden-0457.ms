// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"
fn wrong() Unit:
    algorithm := HashAlgorithm.Sha257
