// conform: tags=try-result,tier-core
// conform: phase=run

// A parameter or local named ok is an ordinary callee; only the prelude constructor
// takes an omitted Void payload.
fn apply(ok fn() Int) Int {
	return ok()
}

fn done() Void! {
	return ok()
}

fn main() Void! {
	ok := () => 7
	print(apply(ok).to_string())
	print(ok().to_string())
	done()?
}
