# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:185 TestPartialReportsRecoveredIssuesInSourceOrder
fn a() Int:
    if true:
        let y = = 3
        let z = 1
    let w = = 4
    return 1
