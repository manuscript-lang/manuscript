# conform: tags=faults,formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:35 TestOptionalArgumentBoundaries
fn f[T](value: T?) T: return value.get()

fn call() Unit: let value = f(none)
