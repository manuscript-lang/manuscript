# conform: tags=generics,interfaces,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:31 TestEmptyFunctionDeclarations
type List[T]:
impl List[T]:
    fn get() T
