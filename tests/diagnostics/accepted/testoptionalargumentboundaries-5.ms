// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:28 TestOptionalArgumentBoundaries
fn f() Int? => return 4
// expect-exit: 0
