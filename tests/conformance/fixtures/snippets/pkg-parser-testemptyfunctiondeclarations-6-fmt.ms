# conform: tags=control-flow,formatter,interfaces,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:16 TestEmptyFunctionDeclarations
impl Error for Failure:
    def message() -> String: ...
