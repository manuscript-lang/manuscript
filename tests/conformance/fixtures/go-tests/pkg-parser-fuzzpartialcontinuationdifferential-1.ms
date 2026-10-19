# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_continuation_test.go:149 FuzzPartialContinuationDifferential
# prefix
fn work(
a: Int,
) Int:
    let bad = = 1
    return 1
