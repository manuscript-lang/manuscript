# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:46 TestRejectSyntax
fn f() Int:
    return values[0, 1]
