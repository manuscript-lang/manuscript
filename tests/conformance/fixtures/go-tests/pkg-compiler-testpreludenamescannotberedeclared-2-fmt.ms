# conform: tags=formatter,maps,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:111 TestPreludeNamesCannotBeRedeclared
type Map[K, V]:
    value: V
