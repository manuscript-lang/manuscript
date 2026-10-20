# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:41 TestRejectSyntax
fn f() Unit:
    fn g() Unit:
        return
