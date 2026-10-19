# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_continuation_test.go:99 TestPartialContinuationDifferential
fn work() Int:
    let bad = = 1
    return 1
