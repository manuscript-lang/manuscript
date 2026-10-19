# conform: tags=parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:149 TestRejectedConformanceVariants
let callback = Callback(increment)
    callback | try expect_equal(expected: callback)
