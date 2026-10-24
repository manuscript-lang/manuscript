# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/frontend/source_test.go:58 TestRecoveredGraphRetainsImportDiagnosticPosition
from "./missing.ms" import missing

def value() -> Int: return 3
