# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/frontend/source_test.go:58 TestRecoveredGraphRetainsImportDiagnosticPosition
import missing from "./missing.ms"

fn value() Int: return 3
