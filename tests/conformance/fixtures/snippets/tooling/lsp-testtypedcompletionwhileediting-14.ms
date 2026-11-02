# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/completion_test.go:141 TestTypedCompletionWhileEditing
fn work() String:
    return "Que|"
