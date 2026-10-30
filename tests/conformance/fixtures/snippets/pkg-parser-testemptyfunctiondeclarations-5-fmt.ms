# conform: tags=formatter,interfaces,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:15 TestEmptyFunctionDeclarations
interface Read:
    fn read(limit: Int? = none) Int
