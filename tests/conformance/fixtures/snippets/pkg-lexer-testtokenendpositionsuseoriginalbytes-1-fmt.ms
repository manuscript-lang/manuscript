# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:83 TestTokenEndPositionsUseOriginalBytes
def f() -> String:
    return "é"  # keep
