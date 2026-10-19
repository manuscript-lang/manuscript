# conform: tags=interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:65 TestLexicalBoundaries
fn value() String:
    return "\u{d800}"
