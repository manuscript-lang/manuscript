# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:23 TestCompressionDefaultCallableBoundaries
let encode = forward(CompressionFormat.Gzip.compress)
    encode("".to_bytes())
