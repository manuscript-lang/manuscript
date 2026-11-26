// conform: tags=decimal,diagnostics,formatter,modules,stdlib-decimal,stdlib-time,tier-io
// conform: phase=check,parse
// conform: origin=tests/e2e/numeric_diagnostics_test.go:39 TestNumericPreconditionDiagnostics
import (
	Decimal from "@std/math/decimal.ms",
	nanoseconds from "@std/time.ms",
)
// expect-exit: 0
