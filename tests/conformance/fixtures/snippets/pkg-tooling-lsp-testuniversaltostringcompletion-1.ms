# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:233 TestUniversalToStringCompletion
fn text(value: Bool) String:
    return value.|
