// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	CompressionError, CompressionFormat, compress from "@std/compress.ms",
)

fn forward[T](item T) T => item
// expect-error: MS2002 5:5-5:21 unknown standard module @std/compress.ms; did you mean '@std/math/complex.ms'?
// expect-error: MS2002 5:23-5:40 unknown standard module @std/compress.ms; CompressionFormat is exported by another standard module, so write: import CompressionFormat from "@std/io/archive.ms"
// expect-error: MS2002 5:42-5:50 unknown standard module @std/compress.ms; compress is exported by another standard module, so write: import compress from "@std/io/archive.ms"
