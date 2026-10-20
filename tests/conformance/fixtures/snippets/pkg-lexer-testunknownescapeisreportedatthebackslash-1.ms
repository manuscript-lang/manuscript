# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:115 TestUnknownEscapeIsReportedAtTheBackslash
let s = "a\qb"
