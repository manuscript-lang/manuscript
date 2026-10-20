# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:37 TestDiagnosticsStateCauseAndFix
fn f(o: Optional[Int]) Int:
    match o:
        Some(v):
            return v
        None:
            return 0
