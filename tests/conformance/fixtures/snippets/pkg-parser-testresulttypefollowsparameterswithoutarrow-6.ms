# conform: tags=closures,diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/parser/result_type_test.go:15 TestResultTypeFollowsParametersWithoutArrow
def f() -> Unit:
    let g = lambda (x: Int) -> Result[Int, String]: ok(x)
    return ()
