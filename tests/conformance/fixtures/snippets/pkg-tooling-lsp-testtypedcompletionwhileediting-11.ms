# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:138 TestTypedCompletionWhileEditing
fn sum(left: Int, right: Int) Int:
    return left + right
fn answer(input: Int) Int:
    return sum(left: inp|
