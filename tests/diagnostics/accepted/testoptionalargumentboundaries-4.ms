// conform: tags=aliasing,diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:27 TestOptionalArgumentBoundaries
fn call() Void {
	_value Int? := 4
}
// expect-exit: 0
