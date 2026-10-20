# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:133 TestTypedCompletionWhileEditing
fn size(text: String) Int:
    return text.byte_|
