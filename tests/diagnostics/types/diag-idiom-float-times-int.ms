// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := 1.0 * 2
}
// expect-error: MS3001 5:14 operator operands require the same independently known type, found Float * Int; convert the Int with value.to_float(), or the Float with value.truncate_to_int() (returns Int?)
// expect-fix: 5:16-5:17 "2.0"
