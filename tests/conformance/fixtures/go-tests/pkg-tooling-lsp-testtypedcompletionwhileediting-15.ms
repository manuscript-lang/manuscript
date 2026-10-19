# conform: tags=optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:142 TestTypedCompletionWhileEditing
fn work(value: Optional[Int]) Int:
    return value.|
