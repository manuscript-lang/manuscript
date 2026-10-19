# conform: tags=aliasing,closures,optional,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:21 TestCompressionDefaultCallableBoundaries
let encode: fn(data: Bytes, format: String, level: Int, max_bytes: Optional[Int]) Result[Bytes, CompressionError] = compress
    encode("".to_bytes(), "gzip")
