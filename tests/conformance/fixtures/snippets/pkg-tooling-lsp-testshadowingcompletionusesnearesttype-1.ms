# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:211 TestShadowingCompletionUsesNearestType
fn answer(input: Int) Unit:
    if true:
        let input = "text"
        inp|
    return unit
