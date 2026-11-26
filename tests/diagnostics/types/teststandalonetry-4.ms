// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/standalone_try_test.go:13 TestStandaloneTry
fn operation() Void! => ok()

fn f() Void {
	operation()?
}
// expect-error: MS3000 7:5 '?' requires an enclosing Result; declare this function to return Result[T, E], or use 'if value := x', '.get_or(default)', or '.get()'
