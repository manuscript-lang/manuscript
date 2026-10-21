# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:9 TestPartialParserPreservesPositionsAndStrictFailure
# prefix
fn good(input: Int) Int:
    return input
fn broken(
fn later() Int:
    return 2
