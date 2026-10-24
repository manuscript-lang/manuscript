# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:37 TestDiagnosticsStateCauseAndFix
def f(o: Optional[Int]) -> Int:
    match o:
        case Some(v):
            return v
        case None:
            return 0
