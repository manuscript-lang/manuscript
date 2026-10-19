# conform: tags=parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:132 TestTypedCompletionWhileEditing
fn count(items: Set[Int]) Int:
    return items.|
