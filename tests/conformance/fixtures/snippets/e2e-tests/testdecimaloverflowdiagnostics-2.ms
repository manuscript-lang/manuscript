# conform: tags=diagnostics,testing,tier-core
# conform: phase=check
# conform: origin=tests/e2e/decimal_overflow_diagnostics_test.go:31 TestDecimalOverflowDiagnostics
test "continues after decimal overflow":
    let finite = 1d / 3d
