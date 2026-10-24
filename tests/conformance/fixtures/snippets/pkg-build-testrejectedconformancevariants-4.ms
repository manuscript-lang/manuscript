# conform: tags=control-flow,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:130 TestRejectedConformanceVariants
impl Increment for Offset:
    def apply(value: Int) -> Int:
        return value + self.delta
