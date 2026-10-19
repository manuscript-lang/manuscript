# conform: tags=closures,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:237 TestUniversalToStringCompletion
fn text(value: fn() Int) String:
    return value.|
