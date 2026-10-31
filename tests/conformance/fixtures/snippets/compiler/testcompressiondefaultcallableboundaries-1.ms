# conform: tags=diagnostics,generics,modules,stdlib-bytes,stdlib-compress,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/compression_defaults_test.go:10 TestCompressionDefaultCallableBoundaries
import compress, CompressionFormat, CompressionError from "@std/archive.ms"
import Bytes from "@std/bytes.ms"

fn forward[T](item: T) T: item
