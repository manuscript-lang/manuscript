# conform: tags=diagnostics,match,optional,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:268 TestTryStatementInsideMatchArm
fn f(x: Int?) Unit!:
    match x:
        n:
            try g(n)
            return ok(unit)
        none: return ok(unit)
