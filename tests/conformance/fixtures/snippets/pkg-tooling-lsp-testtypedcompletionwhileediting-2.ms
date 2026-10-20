# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:129 TestTypedCompletionWhileEditing
fn answer() Int:
    let before = 1
    be|
    let behind = 2
    return before
