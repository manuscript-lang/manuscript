// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/standalone_try_test.go:10 TestStandaloneTry
fn operation() Void! => ok()

fn f() Int! {
	operation()?
	return ok(1)
}
// expect-exit: 0
