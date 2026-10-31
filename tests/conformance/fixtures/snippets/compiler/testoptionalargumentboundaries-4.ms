# conform: tags=aliasing,diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:27 TestOptionalArgumentBoundaries
fn call() Unit:
    let _value: Int? = 4
