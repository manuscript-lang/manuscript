# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:205 TestDefaultCallNavigation
fn read() Int:
    return 1

fn named(value: Int = read()) Int:
    return value
