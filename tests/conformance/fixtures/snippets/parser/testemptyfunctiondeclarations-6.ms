# conform: tags=control-flow,diagnostics,interfaces,strings,tier-core
# conform: phase=check
# conform: origin=pkg/parser/empty_declarations_test.go:16 TestEmptyFunctionDeclarations
impl Error for Failure:
    fn message() String: ...
