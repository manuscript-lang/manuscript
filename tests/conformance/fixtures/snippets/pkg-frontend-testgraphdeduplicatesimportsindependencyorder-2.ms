# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/frontend/source_test.go:29 TestGraphDeduplicatesImportsInDependencyOrder
import value from "./shared.ms"
export fn left() Int: return value()
