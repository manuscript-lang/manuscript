# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:49 TestRejectSyntax
fn f() Unit:
    consume(transform: fn() Unit:
        return
        )
