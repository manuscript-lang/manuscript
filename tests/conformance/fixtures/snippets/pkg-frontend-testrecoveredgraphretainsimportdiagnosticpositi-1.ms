# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/frontend/source_test.go:58 TestRecoveredGraphRetainsImportDiagnosticPosition
from "./missing.ms" import missing

def value() -> Int: return 3
