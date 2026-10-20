# conform: tags=control-flow,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:165 BenchmarkClosedMapProofScaling
type Key%d:
    value: Int
impl Tag for Key%d:
    fn tag() Int: self.value
