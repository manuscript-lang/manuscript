// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := [1].reduce(0, fn(a Int, b Int) Int => a + b)
}
// expect-error: MS2001 5:14 unknown or ambiguous member reduce on List[Int]; did you mean 'fold'?
// expect-fix: 5:14-5:20 "fold"
