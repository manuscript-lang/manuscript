# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:260 TestFuzzyMemberCompletion
fn size(text: String) Int:
    return text.bl|
