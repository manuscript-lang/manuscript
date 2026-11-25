// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a double := 1.0
}
// expect-error: MS2001 5:7 unknown type double; did you mean 'Float'?
// expect-fix: 5:7-5:13 "Float"
