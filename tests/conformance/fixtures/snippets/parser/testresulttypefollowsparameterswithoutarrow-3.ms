// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/result_type_test.go:12 TestResultTypeFollowsParametersWithoutArrow
fn f() Int {
	g := fn(x) Int => x + 1
	h := x => x + 1
	return g(1) + h(2)
}
// expect-error: MS3080 5:13 cannot infer callback parameter x; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
// expect-error: MS3080 6:10 cannot infer callback parameter x; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
