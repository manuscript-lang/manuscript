# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:24 TestDiagnosticFixes
type Box[Hashable]:
    v: Hashable
