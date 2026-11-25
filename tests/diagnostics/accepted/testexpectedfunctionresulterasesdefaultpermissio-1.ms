// conform: tags=closures,diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/contextual_inference_test.go:46 TestExpectedFunctionResultErasesDefaultPermissions
fn from_callback[T](factory fn() T) T => factory()

fn first() Void {
	_callback fn(Int) Int := from_callback(() => fn(value Int = 4) => value)
}
// expect-exit: 0
