# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:145 TestSymbolRangesAndInferredTypeHints
fn answer() Int:
    let number = 42
    return number
fn later() Int:
    return 2
