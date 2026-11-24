// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:38 TestOptionalArgumentBoundaries
fn f(value Int?) Void: return

fn call() Void: f(other: 4)
