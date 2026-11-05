// conform: tags=alternatives,formatter,generics,interfaces,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/parser/empty_declarations_test.go:13 TestEmptyFunctionDeclarations
enum Optional[T]:
    none
    T

impl T?:
    fn get() T: ...
