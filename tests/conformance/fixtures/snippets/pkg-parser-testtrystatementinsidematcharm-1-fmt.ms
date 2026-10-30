# conform: tags=formatter,match,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:268 TestTryStatementInsideMatchArm
fn f(x: Int?) Result[Unit, Error]:
    match x:
        some(n):
            try g(n)
            return ok(unit)
        none: return ok(unit)
