// conform: tags=diagnostics
// conform: phase=check
fn work() Int {
	value := [2, 5, 3, (-6), (-9), 1, 2, 3, 4].clone().sorted(
		fn(l Int, r Int) Int => (l - r)
	).first()
	if value != null { return value }

	return 0
}
// expect-exit: 0
