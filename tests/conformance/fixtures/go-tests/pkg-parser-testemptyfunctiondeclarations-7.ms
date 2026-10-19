# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/parser/empty_declarations_test.go:17 TestEmptyFunctionDeclarations
type Options:
    count: Int = 3
    total: Int = count + 1
