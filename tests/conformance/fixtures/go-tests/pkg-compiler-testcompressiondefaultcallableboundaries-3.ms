# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:20 TestCompressionDefaultCallableBoundaries
let encode = forward(compress)
    encode("".to_bytes(), "gzip")
