# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/lexer_test.go:83 TestTokenEndPositionsUseOriginalBytes
fn f() String:
    return "é" # keep
