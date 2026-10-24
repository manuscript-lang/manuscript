# conform: tags=formatter,generics,modules,parser,stdlib-bytes,stdlib-compress,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:10 TestCompressionDefaultCallableBoundaries
from "@std/archive.ms" import compress, CompressionFormat, CompressionError
from "@std/bytes.ms" import Bytes

def forward[T](item: T) -> T: item
