// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	var outer = 1
	callback := fn(
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
// expect-error: MS3000 5:5 local binding callback is never read; remove it, use it, or name it with a leading '_' to ignore it
