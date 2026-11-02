# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:117 TestPreludeNamesCannotBeRedeclared
fn ok(value: Int) Int: value
