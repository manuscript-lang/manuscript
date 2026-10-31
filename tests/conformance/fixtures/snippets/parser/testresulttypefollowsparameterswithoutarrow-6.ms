# conform: tags=closures,diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/parser/result_type_test.go:15 TestResultTypeFollowsParametersWithoutArrow
fn f() Unit:
    let g = fn(x: Int) Int!String: ok(x)
    return unit
