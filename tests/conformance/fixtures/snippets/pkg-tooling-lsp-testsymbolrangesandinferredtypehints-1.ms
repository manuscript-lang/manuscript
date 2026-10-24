# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:145 TestSymbolRangesAndInferredTypeHints
def answer() -> Int:
    let number = 42
    return number

def later() -> Int:
    return 2
