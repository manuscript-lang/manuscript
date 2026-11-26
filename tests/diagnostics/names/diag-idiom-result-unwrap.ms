// conform: tags=diagnostics,try-result,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn f() Int! {
	return ok(1)
}

fn main() Void {
	x := f().unwrap()
}
// expect-error: MS2001 9:14 unknown or ambiguous member unwrap on Int!; read a Result with `x?` inside a fn that returns Result, x.get_or(default), x.get_or_else(create) for a lazy fallback, or `if value := x { ... }`
