// conform: tags=closures,diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:37 TestOptionalArgumentBoundaries
fn f(value Int) Int => return value

fn call() Void {
	callback fn(Int?) Int := f
}
// expect-error: MS3001 7:30 expected fn(Int?) Int, found fn(Int) Int (in the initializer of 'callback')
