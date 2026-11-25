// conform: tags=diagnostics
// conform: phase=check
fn required(value Int) Int => value

fn first() Void {
	var callback fn(Int) Int = from_callback(() => fn(value Int = 4) => value)
	callback = required
	callback()
}
// expect-error: MS2001 6:32 unknown binding from_callback; declare it with 'from_callback := ...' before use, define 'fn from_callback(...) T { ... }', or import it from a module
// expect-error: MS3003 8:5 missing argument 1: Int in call to callback; pass it positionally, without a label
