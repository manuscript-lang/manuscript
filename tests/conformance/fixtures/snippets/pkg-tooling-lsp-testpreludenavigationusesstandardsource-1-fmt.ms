# conform: tags=faults,formatter,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:109 TestPreludeNavigationUsesStandardSource
def work(value: Optional[Int]) -> Result[Int, Error]:
    return ok(value: value.get())
