# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/defaults_test.go:59 TestDefaultArgumentEditorSupport
fn combine(first: Int = 3, second: Int = fir|) Int:
    return second
