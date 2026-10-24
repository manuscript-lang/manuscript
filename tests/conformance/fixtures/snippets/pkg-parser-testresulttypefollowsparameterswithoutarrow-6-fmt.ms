# conform: tags=closures,formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:15 TestResultTypeFollowsParametersWithoutArrow
def f() -> Unit:
    let g = lambda (x: Int) -> Result[Int, String]: ok(x)
    return ()
