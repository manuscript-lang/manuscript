// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_test.go:174 TestFormatInlineSuites
fn double(x Int) Int => return x * 2

fn f(x Int) Int {
	if x > 0 {
		return double(x)
	} else {
		return 0
	}
}
// expect-exit: 0
