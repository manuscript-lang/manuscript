# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/frontend/source_test.go:58 TestRecoveredGraphRetainsImportDiagnosticPosition
import missing from "./missing.ms"

fn value() Int: return 3
