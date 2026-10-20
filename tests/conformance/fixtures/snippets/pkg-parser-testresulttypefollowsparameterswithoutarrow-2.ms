# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/result_type_test.go:11 TestResultTypeFollowsParametersWithoutArrow
fn f(g: fn(value: Int) Int) fn(value: Int) Int:
    return g
