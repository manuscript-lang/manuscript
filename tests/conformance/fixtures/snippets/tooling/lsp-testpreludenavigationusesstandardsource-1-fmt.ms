# conform: tags=faults,formatter,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:109 TestPreludeNavigationUsesStandardSource
fn work(value: Int?) Int!:
    return ok(value: value.get())
