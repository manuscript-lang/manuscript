// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/invalid_operand_test.go:17 TestInvalidOperandsReportOnce
X := nope
Y := X + X
// expect-error: MS2001 4:6 unknown binding nope; declare it with 'nope := ...' before use, define 'fn nope(...) T { ... }', or import it from a module
