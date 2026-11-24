// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	use(
		fn(value, other Int) {
			return value + other
		}
	)
}
