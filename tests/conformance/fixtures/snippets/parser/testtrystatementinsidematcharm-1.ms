// conform: tags=diagnostics,match,optional,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/parser/parser_test.go:268 TestTryStatementInsideMatchArm
fn f(x: Int?) Void!:
    match x:
        n:
            g(n)?
            return ok()
        null: return ok()
