# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:40 TestRejectSyntax
fn f() Unit:
    (1 + 2) = 1
