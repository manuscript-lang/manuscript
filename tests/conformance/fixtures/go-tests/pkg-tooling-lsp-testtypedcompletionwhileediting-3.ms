# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:130 TestTypedCompletionWhileEditing
fn answer() Int:
    if true:
        let secret = 1
    sec|
    return 0
