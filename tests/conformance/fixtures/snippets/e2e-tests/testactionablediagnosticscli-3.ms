// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=tests/e2e/diagnostics_test.go:20 TestActionableDiagnosticsCLI
import money from "./money.ms"
// expect-error: MS2002 4:1 cannot find module ./money.ms (looked for money.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
