// conform: tags=diagnostics,match,alternatives,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
enum S {
	A
	B(x Int)
}

fn f(s S) Int {
	match s {
		A => {
			return 1
		}
	}
}

fn main() Void {
	return
}
// expect-error: MS3050 10:5 non-exhaustive match; missing cases: B, or add a final '_ => ...' arm; add the arms 'B(x) => ...'
