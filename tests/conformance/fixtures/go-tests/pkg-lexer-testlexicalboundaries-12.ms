# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:64 TestLexicalBoundaries
fn value() String:
    return "a	b"
