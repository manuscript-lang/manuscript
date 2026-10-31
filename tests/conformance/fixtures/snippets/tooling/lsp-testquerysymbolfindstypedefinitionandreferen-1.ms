# conform: tags=functions,tier-core
# conform: phase=run
# conform: origin=pkg/tooling/lsp/query_test.go:13 TestQuerySymbolFindsTypeDefinitionAndReferences
fn double(value: Int) Int:
    return value * 2

export fn main() Int:
    let x = double(4)
    return x - 8
