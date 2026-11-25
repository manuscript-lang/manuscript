// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := String(1)
}
// expect-error: MS3000 5:10 this type has no source constructor: String is built in; write a literal or call a standard function that returns it; make text with interpolation f"{value}" or value.to_string()
