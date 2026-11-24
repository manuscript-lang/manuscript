// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"
import CompressionFormat from "@std/compress.ms"
fn choose(algorithm HashAlgorithm) Void:
    return
fn wrong() Void:
    choose(CompressionFormat.Gzip)
