# conform: tags=aliasing,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:27 TestOptionalArgumentBoundaries
fn call() Unit:
    let value: Optional[Int] = 4
