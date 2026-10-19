# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:17 TestEmptyFunctionDeclarations
type Options:
    count: Int = 3
    total: Int = count + 1
