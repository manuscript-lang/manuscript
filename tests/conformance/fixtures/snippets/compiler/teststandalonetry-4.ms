// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/standalone_try_test.go:13 TestStandaloneTry
fn operation() Void! => ok()

fn f() Void {
	operation()?
}
