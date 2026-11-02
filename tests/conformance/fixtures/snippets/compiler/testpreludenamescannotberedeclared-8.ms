# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:117 TestPreludeNamesCannotBeRedeclared
fn ok(value: Int) Int: value
