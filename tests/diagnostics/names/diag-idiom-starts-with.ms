// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := "x".startsWith("x")
}
// expect-error: MS2001 5:14 unknown or ambiguous member startsWith on String; did you mean 'starts_with'?
// expect-fix: 5:14-5:24 "starts_with"
