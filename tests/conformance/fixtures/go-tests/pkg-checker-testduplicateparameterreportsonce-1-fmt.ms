# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/duplicate_parameter_test.go:15 TestDuplicateParameterReportsOnce
fn f(a: Int, a: Int) Int:
    return a
