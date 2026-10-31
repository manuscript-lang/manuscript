# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:33 TestOptionalArgumentBoundaries
fn f[T](first: T?, second: T) Unit: return

fn call() Unit: f(first: 4, second: "wrong")
