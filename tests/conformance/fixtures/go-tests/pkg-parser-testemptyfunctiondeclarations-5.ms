# conform: tags=diagnostics,interfaces,optional,tier-core
# conform: phase=check
# conform: origin=pkg/parser/empty_declarations_test.go:15 TestEmptyFunctionDeclarations
interface Read:
    fn read(limit: Optional[Int] = none) Int
