// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := "x".toUpperCase()
}
// expect-error: MS2001 5:14 unknown or ambiguous member toUpperCase on String; did you mean 'upper'?
// expect-fix: 5:14-5:25 "upper"
