// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/int_bounds_test.go:37 TestScalarIntBoundsLowering
fn identity[T](hold value T) &T => return value

fn effect(value Int) Int => return value + 1
// expect-exit: 0
