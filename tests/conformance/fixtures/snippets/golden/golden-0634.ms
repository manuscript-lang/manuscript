// conform: tags=diagnostics
// conform: phase=check
fn f(value Int) Int => return value

fn call() Void {
	callback fn(Int?) Int := f
}
