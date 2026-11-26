// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/standalone_try_test.go:14 TestStandaloneTry
fn operation() Void => void

fn f() Int! {
	operation()?
	return ok(1)
}
// expect-error: MS3000 7:5 '?' requires a Result or an Optional, found Void; apply '?' to a value of type Result[T, E] or T?
