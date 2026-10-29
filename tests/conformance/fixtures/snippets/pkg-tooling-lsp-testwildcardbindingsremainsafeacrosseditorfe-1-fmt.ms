# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:178 TestWildcardBindingsRemainSafeAcrossEditorFeatures
fn answer(value: Optional[Int]) Int:
    match value:
        some(_):
            return 1
        none:
            return 0
