# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/lower/int_bounds_test.go:163 BenchmarkClosedMapProofScaling
interface Tag:
    def tag() -> Int
