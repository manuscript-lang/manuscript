// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"
fn choose(algorithm: HashAlgorithm) Unit:
    return unit
fn wrong() Unit:
    choose("sha256")
