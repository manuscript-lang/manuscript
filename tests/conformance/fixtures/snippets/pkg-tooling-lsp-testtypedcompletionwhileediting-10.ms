# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:137 TestTypedCompletionWhileEditing
fn sum(left: Int, right: Int) Int:
    return left + right
fn answer() Int:
    return sum(left: 1, |
