# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:114 TestPreludeNamesCannotBeRedeclared
interface Equal:
    def same() -> Bool
