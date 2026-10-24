# conform: tags=control-flow,formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:130 TestRejectedConformanceVariants
impl Increment for Offset:
    def apply(value: Int) -> Int:
        return value + self.delta
