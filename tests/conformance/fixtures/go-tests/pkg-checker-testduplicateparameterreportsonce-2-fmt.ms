# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/duplicate_parameter_test.go:16 TestDuplicateParameterReportsOnce
fn f() Int:
    let g = fn(a: Int, a: Int) Int: return a
    return 1
