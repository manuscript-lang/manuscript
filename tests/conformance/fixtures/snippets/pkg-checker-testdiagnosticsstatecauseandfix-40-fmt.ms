# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:59 TestDiagnosticsStateCauseAndFix
def f() -> String:
    return [1].join(separator: ",")
