# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/defaults_test.go:66 TestRenameParameterUsedInDefault
def combine(first: Int = 3, second: Int = first) -> Int:
    return first + second
