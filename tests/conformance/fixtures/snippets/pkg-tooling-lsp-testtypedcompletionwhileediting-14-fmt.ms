# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:141 TestTypedCompletionWhileEditing
fn work() String:
    return "Que|"
