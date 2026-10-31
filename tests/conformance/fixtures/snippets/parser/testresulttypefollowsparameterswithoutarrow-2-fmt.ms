# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:11 TestResultTypeFollowsParametersWithoutArrow
fn f(g: fn(Int) Int) fn(Int) Int:
    return g
