# conform: tags=generics,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:32 TestEmptyFunctionDeclarations
type List[T]:
    fn get() T:
