// conform: tags=diagnostics,numbers,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:25 TestOptionalArgumentBoundaries
fn f(value Float?) Void: return

fn call() Void: f(4)
