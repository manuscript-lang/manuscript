# conform: tags=closures,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:24 TestCompressionDefaultCallableBoundaries
let encode: fn(data: Bytes, level: Int, max_bytes: Optional[Int]) Result[Bytes, CompressionError] = CompressionFormat.Gzip.compress
    encode("".to_bytes())
