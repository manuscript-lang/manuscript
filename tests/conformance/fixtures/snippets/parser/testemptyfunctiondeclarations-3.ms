# conform: tags=alternatives,diagnostics,generics,interfaces,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/parser/empty_declarations_test.go:13 TestEmptyFunctionDeclarations
type Optional[T]:
    case none
    case T

impl T?:
    fn get() T: ...
