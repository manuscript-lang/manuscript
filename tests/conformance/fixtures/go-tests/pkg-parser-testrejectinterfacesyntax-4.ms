# conform: tags=interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:137 TestRejectInterfaceSyntax
interface Read:
    fn get() Int:
        return 1
