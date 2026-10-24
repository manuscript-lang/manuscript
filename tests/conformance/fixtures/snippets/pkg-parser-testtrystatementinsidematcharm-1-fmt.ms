# conform: tags=formatter,match,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:268 TestTryStatementInsideMatchArm
def f(x: Optional[Int]) -> Result[Unit, Error]:
    match x:
        case some(n):
            try g(n)
            return ok(())
        case none: return ok(())
