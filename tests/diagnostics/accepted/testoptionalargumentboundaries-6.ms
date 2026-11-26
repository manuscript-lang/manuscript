// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:29 TestOptionalArgumentBoundaries
fn f(value Int? = 4) Void => return
// expect-exit: 0
