# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:178 TestWildcardBindingsRemainSafeAcrossEditorFeatures
fn answer(value: Int?) Int:
    match value:
        _value:
            return 1
        none:
            return 0
