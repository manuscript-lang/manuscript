// conform: tags=diagnostics,generics,modules,stdlib-bytes,stdlib-compress,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/compression_defaults_test.go:10 TestCompressionDefaultCallableBoundaries
import (
	Bytes from "@std/bytes.ms",
	CompressionFormat, compress from "@std/io/archive.ms",
)

fn forward[T](hold item T) &T => item
// expect-exit: 0
