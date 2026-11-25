// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:80 TestCallArgumentLabelRejections
fn call(operation fn() Int) Int {
	return operation()
}
// expect-exit: 0
