# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:24 TestDiagnosticFixes
type Box[Hashable]:
    v: Hashable
