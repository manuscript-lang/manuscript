// conform: tags=formatter,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/prelude_test.go:116 TestPreludeNamesCannotBeRedeclared
fn Int Int: value
// expect-error: MS1000 4:8-4:11 expected '(', found name 'Int'; a call or parameter list starts with '('
// expect-format-exit: 1
