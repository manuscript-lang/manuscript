# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/positions_test.go:24 TestMixedLineEndingPositions
# first
fn value() Int:
    return [1)
