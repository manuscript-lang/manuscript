# conform: tags=diagnostics,interpolation,strings,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/lexer_test.go:76 TestLexicalBoundaries
def value() -> String:
    return f"héllo \u{1F600} {1 + 2} \{literal\}"
