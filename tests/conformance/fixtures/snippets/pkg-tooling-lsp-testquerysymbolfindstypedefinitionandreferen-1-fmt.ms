# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/query_test.go:13 TestQuerySymbolFindsTypeDefinitionAndReferences
def double(value: Int) -> Int:
    return value * 2

export def main() -> Int:
    let x = double(4)
    return x - 8
