# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:37 TestDiagnosticsStateCauseAndFix
def f(o: Optional[Int]) -> Int:
    match o:
        case Some(v):
            return v
        case None:
            return 0
