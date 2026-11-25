// conform: tags=diagnostics
// conform: phase=check
fn from_callback[T](factory fn() T) T => factory()

fn first() Void {
	callback fn(Int) Int := from_callback(() => fn(value Int = 4) => value)
}
// expect-error: MS3000 6:5 local binding callback is never read; remove it, use it, or name it with a leading '_' to ignore it
