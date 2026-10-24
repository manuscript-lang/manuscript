# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:116 TestPreludeNamesCannotBeRedeclared
def some(value: Int) -> Int: value
