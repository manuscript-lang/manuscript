# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/duplicate_parameter_test.go:15 TestDuplicateParameterReportsOnce
def f(a: Int, a: Int) -> Int:
    return a
