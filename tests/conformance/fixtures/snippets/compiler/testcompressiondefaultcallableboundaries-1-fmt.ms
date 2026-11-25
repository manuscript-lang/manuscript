// conform: tags=formatter,generics,modules,parser,stdlib-bytes,stdlib-compress,tier-stdlib
// conform: phase=parse
// conform: origin=pkg/compiler/compression_defaults_test.go:10 TestCompressionDefaultCallableBoundaries
import (
	Bytes from "@std/bytes.ms",
	CompressionFormat, compress from "@std/io/archive.ms",
)

fn forward[T](item T) T => item
