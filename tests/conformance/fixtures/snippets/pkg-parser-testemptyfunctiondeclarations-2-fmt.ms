# conform: tags=closures,formatter,generics,interfaces,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:12 TestEmptyFunctionDeclarations
type List[T]:

impl List[T]:
    fn map[U](transform: fn(value: T) U) List[U]:

    fn length() Int:
