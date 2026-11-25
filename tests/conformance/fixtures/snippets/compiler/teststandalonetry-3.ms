// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/standalone_try_test.go:12 TestStandaloneTry
fn operation() Void!Int => ok()

fn f() Int! {
	operation()?
	return ok(1)
}
// expect-error: MS3000 7:5 '?' requires the same error type; this function returns Result[Int, Error] but the operand fails with Int, so change the return error type or translate the error with map_error
