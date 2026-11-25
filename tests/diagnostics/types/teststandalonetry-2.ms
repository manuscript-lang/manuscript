// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/standalone_try_test.go:11 TestStandaloneTry
fn operation() Int! => ok(1)

fn f() Int! {
	operation()?
	return ok(1)
}
// expect-error: MS3000 7:5 a standalone '?' requires a Void success value, found Int; use 'name := call()?' to keep the value or 'return call()?' to return it
