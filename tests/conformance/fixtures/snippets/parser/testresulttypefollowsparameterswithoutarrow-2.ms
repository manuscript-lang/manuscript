// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/result_type_test.go:11 TestResultTypeFollowsParametersWithoutArrow
fn f(g fn(Int) Int) fn(Int) Int {
	return g
}
// expect-exit: 0
