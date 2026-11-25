// conform: tags=closures,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:29 TestDefaultArgumentBoundaries
fn f() Void {
	var outer = 1
	_callback := fn(
		value Int = (
			fn() Int {
				outer = 2
				return outer
			}
		)()
	) Int {
		return value
	}
}
// expect-exit: 0
