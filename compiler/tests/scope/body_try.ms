// `?` on a call that returns a Result of the function's own error type, and Results that are discarded.
fn halve(n: Int) Int!:
	return ok(n / 2)

fn check(n: Int) Void!:
	return ok(void)

fn guarded(n: Int) Void!:
	check(n)?

	value := halve(n)?
	if value > 1: return

fn lost(n: Int) Void!:
	halve(n)
	check(n)
