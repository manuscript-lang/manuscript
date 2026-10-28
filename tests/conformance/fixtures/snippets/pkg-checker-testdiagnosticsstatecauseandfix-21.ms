# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:40 TestDiagnosticsStateCauseAndFix
fn p() Result[Int, Error]:
    return ok(1)

fn f() Int:
    return p() + 1
