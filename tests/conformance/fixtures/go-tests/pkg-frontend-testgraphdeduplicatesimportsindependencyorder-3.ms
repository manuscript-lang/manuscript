# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/frontend/source_test.go:30 TestGraphDeduplicatesImportsInDependencyOrder
import value from "./shared.ms"
export fn right() Int: return value()
