# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:119 TestPreludeNamesCannotBeRedeclared
fn error(value: Int) Int: value
