# conform: tags=mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:19 TestCompressionDefaultCallableBoundaries
var encode = compress
    encode("".to_bytes(), "gzip")
