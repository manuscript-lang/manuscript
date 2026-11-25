// conform: tags=diagnostics,types,try-result,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn f() Int! {
	return 1
}

fn main() Void {
	return
}
// expect-error: MS3001 5:12 expected Result[Int, Error], found Int (in the return value); wrap the value in ok(...) to return it as a success, e.g. return ok(value); when another argument is a Result call, unwrap that call with ? instead, e.g. expect_equal(f()?, value)?
