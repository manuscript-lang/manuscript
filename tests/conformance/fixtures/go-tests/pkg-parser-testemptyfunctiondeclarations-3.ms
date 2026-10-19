# conform: tags=alternatives,diagnostics,generics,interfaces,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/parser/empty_declarations_test.go:13 TestEmptyFunctionDeclarations
type Optional[T]:
    case none
    case some(value: T)
impl Optional[T]:
    fn get() T:
