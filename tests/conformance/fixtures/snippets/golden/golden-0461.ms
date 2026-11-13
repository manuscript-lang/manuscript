// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"
import CompressionFormat from "@std/compress.ms"
fn choose(algorithm: HashAlgorithm) Unit:
    return unit
fn wrong() Unit:
    choose(CompressionFormat.Gzip)
