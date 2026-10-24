# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/duplicate_parameter_test.go:16 TestDuplicateParameterReportsOnce
def f() -> Int:
    let g = lambda (a: Int, a: Int) -> Int: return a
    return 1
