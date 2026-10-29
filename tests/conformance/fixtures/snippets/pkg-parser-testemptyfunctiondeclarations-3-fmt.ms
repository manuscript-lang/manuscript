# conform: tags=alternatives,formatter,generics,interfaces,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:13 TestEmptyFunctionDeclarations
type Optional[T]:
    case none
    case some(value: T)

impl Optional[T]:
    fn get() T: ...
