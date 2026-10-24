# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:178 TestWildcardBindingsRemainSafeAcrossEditorFeatures
def answer(value: Optional[Int]) -> Int:
    match value:
        case some(_):
            return 1
        case none:
            return 0
