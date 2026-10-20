# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:114 TestPreludeNamesCannotBeRedeclared
interface Equal:
    fn same() Bool
