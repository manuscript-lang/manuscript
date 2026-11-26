// conform: tags=diagnostics
// conform: phase=check
fn f(value Int) Int => return value

fn call() Void {
	callback fn(Int?) Int := f
}
// expect-error: MS3001 6:30 expected fn(Int?) Int, found fn(Int) Int (in the initializer of 'callback')
