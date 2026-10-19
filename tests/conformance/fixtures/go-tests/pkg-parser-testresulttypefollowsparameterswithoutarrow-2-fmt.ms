# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:11 TestResultTypeFollowsParametersWithoutArrow
fn f(g: fn(value: Int) Int) fn(value: Int) Int:
    return g
