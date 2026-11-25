// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	g := fn(x) Int => x
	return 0
}
// expect-error: MS3080 4:13 cannot infer callback parameter x; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
