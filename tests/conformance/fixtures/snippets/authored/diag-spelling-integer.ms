// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a Integer := 1
}
// expect-error: MS2001 5:7 unknown type Integer; did you mean 'Int'?
// expect-fix: 5:7-5:14 "Int"
