# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:131 TestRejectedConformanceVariants
fn apply(item: Int) Int:
        return item + self.delta
