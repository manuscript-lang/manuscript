# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:47 TestRejectSyntax
fn f() Unit:
    for [key, value] in entries:
        return
