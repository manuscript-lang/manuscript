# conform: tags=mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/compression_defaults_test.go:22 TestCompressionDefaultCallableBoundaries
var encode = CompressionFormat.Gzip.compress
    encode("".to_bytes())
