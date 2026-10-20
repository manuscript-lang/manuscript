# conform: tags=lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:131 TestTypedCompletionWhileEditing
fn count(items: List[Int]) Int:
    return items.|
