// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := [1].includes(1)
}
// expect-error: MS2001 5:14 unknown or ambiguous member includes on List[Int]; did you mean 'contains'?
// expect-fix: 5:14-5:22 "contains"
