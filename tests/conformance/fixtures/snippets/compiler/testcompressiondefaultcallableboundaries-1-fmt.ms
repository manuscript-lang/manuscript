# conform: tags=formatter,generics,modules,parser,stdlib-bytes,stdlib-compress,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:10 TestCompressionDefaultCallableBoundaries
import compress, CompressionFormat from "@std/io/archive.ms"
import Bytes from "@std/bytes.ms"

fn forward[T](item: T) T: item
