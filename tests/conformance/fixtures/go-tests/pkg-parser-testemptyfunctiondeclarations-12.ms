# conform: tags=parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:33 TestEmptyFunctionDeclarations
type A:
    x: Int
    fn f() Int:
        return x
