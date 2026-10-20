# conform: tags=generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:139 TestRejectInterfaceSyntax
interface Read:
    fn get[T]() T
