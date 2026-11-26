// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/frontend/source_test.go:58 TestRecoveredGraphRetainsImportDiagnosticPosition
import missing from "./missing.ms"

fn value() Int => return 3
// expect-error: MS2002 4:1 cannot find module ./missing.ms (looked for missing.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
