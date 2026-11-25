// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := Some(1)
}
// expect-error: MS2001 5:10 unknown binding Some; there is no Some: a plain value converts where an Optional is expected, so pass it directly
