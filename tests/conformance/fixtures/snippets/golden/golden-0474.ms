// conform: tags=diagnostics
// conform: phase=check
import compress, CompressionFormat, CompressionError from "@std/compress.ms"
import Bytes from "@std/bytes.ms"
fn forward[T](item: T) T: item
