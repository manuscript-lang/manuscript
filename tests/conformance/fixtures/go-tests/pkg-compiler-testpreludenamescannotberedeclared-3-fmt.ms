# conform: tags=formatter,parser,records,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:112 TestPreludeNamesCannotBeRedeclared
type Set[T]:
    value: T
