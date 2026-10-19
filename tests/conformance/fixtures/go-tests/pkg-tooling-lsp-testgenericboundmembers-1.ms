# conform: tags=generics,interfaces,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:225 TestGenericBoundMembers
interface Reader:
    fn read() String
fn answer[T: Reader](reader: T) String:
    return reader.|
