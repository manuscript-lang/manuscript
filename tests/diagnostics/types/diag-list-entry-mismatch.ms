// conform: tags=diagnostics,lists,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	l := [1, "a"]
}
// expect-error: MS3001 5:14 expected Int, found String (in entry 2 of the literal, whose entries share one type)
