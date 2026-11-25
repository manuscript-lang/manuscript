// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := Int("1")
}
// expect-error: MS3000 5:10 this type has no source constructor: Int is built in; write a literal or call a standard function that returns it; parse text with text.parse_int() (Int?); Float has truncate_to_int()
