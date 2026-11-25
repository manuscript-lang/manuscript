// conform: tags=diagnostics
// conform: phase=check
enum Expr {
	Num(value Int)
	Add(left Expr, right Expr)
}

fn value(expr Expr) Int {
	match expr {
		Num(value) => return value
	}
}
// expect-error: MS3050 9:5 non-exhaustive match; missing cases: Add, or add a final '_ => ...' arm; add the arms 'Add(left, right) => ...'
