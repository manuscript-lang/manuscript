// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := True
}
// expect-error: MS2001 5:10 unknown binding True; booleans are lowercase: write true and false
// expect-fix: 5:10-5:14 "true"
