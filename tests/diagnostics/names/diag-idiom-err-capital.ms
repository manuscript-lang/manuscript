// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := Err(1)
}
// expect-error: MS2001 5:10 unknown binding Err; write error(cause) for a failed Result, where cause has the Result's error type
// expect-fix: 5:10-5:13 "error"
