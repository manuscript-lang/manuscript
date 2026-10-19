# conform: tags=closures,formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:15 TestResultTypeFollowsParametersWithoutArrow
fn f() Unit:
    let g = fn(x: Int) Result[Int, String]: ok(x)
    return unit
