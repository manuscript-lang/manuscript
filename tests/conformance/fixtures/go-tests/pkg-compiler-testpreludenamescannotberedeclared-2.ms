# conform: tags=diagnostics,maps,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:111 TestPreludeNamesCannotBeRedeclared
type Map[K, V]:
    value: V
