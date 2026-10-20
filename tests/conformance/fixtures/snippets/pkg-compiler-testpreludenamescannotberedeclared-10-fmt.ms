# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:119 TestPreludeNamesCannotBeRedeclared
fn error(value: Int) Int: value
