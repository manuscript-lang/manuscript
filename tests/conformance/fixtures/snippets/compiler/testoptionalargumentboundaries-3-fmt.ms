// conform: tags=formatter,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:26 TestOptionalArgumentBoundaries
fn f(value Int?) Void: return

fn call() Void: f()
