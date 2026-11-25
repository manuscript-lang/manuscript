// conform: tags=closures,diagnostics,formatter,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/parser/result_type_test.go:15 TestResultTypeFollowsParametersWithoutArrow
fn f() Void {
	g := fn(x Int) Int!String => ok(x)
	return
}
// expect-error: MS3000 5:5 local binding g is never read; remove it, use it, or name it with a leading '_' to ignore it
