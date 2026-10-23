# conform: tags=closures,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:37 TestOptionalArgumentBoundaries
fn f(value: Int) Int: return value

fn call() Unit:
    let callback: fn(value: Optional[Int]) Int = f
