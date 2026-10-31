# conform: tags=diagnostics,records,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:112 TestPreludeNamesCannotBeRedeclared
type Set[T]:
    value: T
