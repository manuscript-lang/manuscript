# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:36 TestRejectSyntax
fn f() Bool:
    return 1 < 2 < 3
