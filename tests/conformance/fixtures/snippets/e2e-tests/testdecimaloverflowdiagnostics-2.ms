// conform: tags=diagnostics,testing,tier-core
// conform: phase=check
// conform: origin=tests/e2e/decimal_overflow_diagnostics_test.go:31 TestDecimalOverflowDiagnostics
test "continues after decimal overflow" {
	finite := 1d / 3d
}
// expect-error: MS2002 5:15 Decimal literal requires the canonical Decimal import; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"
