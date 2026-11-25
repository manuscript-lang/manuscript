// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	x String := 1
}
// expect-error: MS3001 5:17 expected String, found Int (in the initializer of 'x'); Int does not convert to String implicitly; interpolate it into text, e.g. f"{value}"
// expect-fix: 5:17-5:18 "\"1\""
