# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/frontend/source_test.go:31 TestGraphDeduplicatesImportsInDependencyOrder
import left from "./left.ms"
import right from "./right.ms"
fn result() Int: return left() + right()
