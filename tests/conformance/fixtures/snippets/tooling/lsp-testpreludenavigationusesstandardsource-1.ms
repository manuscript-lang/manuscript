# conform: tags=diagnostics,faults,optional,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/lsp/completion_test.go:109 TestPreludeNavigationUsesStandardSource
fn work(value: Int?) Int!:
    return ok(value: value.get())
