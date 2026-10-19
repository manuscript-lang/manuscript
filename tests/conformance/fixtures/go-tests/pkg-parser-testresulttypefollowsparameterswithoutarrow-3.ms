# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/result_type_test.go:12 TestResultTypeFollowsParametersWithoutArrow
fn f() Int:
    let g = fn(x) Int: x + 1
    let h = fn(x): x + 1
    return g(1) + h(2)
