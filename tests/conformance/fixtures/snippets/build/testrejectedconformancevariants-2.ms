# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:108 TestRejectedConformanceVariants
fn increase(value: Int) Int:
    return value + 1
