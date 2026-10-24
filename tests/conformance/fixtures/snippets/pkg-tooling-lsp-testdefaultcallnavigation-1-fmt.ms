# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:205 TestDefaultCallNavigation
def read() -> Int:
    return 1

def named(value: Int = read()) -> Int:
    return value
