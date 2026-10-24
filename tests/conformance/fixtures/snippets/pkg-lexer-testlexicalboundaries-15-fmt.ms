# conform: tags=formatter,interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:76 TestLexicalBoundaries
def value() -> String:
    return f"héllo \u{1F600} {1 + 2} \{literal\}"
