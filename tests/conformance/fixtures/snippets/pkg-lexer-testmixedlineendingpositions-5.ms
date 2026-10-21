# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/positions_test.go:20 TestMixedLineEndingPositions
# first
fn value() String:
    return "a\q"
