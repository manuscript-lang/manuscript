# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:163 BenchmarkClosedMapProofScaling
interface Tag:
    def tag() -> Int
