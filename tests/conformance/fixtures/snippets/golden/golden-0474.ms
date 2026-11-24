// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	CompressionError, CompressionFormat, compress from "@std/compress.ms",
)

fn forward[T](item T) T => item
