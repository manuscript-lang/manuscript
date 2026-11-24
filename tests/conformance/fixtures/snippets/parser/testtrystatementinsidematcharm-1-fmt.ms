// conform: tags=formatter,match,optional,parser,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/parser/parser_test.go:268 TestTryStatementInsideMatchArm
fn f(x Int?) Void!:
    match x:
        n:
            g(n)?
            return ok()
        null => return ok()
