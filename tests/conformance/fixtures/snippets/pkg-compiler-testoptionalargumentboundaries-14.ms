# conform: tags=closures,diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:37 TestOptionalArgumentBoundaries
fn f(value: Int) Int: return value

fn call() Unit:
    let callback: fn(Int?) Int = f
