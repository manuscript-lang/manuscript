// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/result_type_test.go:10 TestResultTypeFollowsParametersWithoutArrow
fn f(x Int) Int => x
// expect-exit: 0
