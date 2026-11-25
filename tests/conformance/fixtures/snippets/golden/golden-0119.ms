// conform: tags=diagnostics
// conform: phase=check
fn optional(value Int = 1) Int => return value

fn required(value Int) Int => return value

fn call(x Int?) Int {
	chosen := match x {
		n => optional
		null => required
	}

	return chosen()
}
// expect-error: MS3003 13:12 missing argument 1: Int in call to chosen; pass it positionally, without a label
