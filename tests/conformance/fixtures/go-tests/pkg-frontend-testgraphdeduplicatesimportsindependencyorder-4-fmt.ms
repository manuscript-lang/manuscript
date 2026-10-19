# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/frontend/source_test.go:31 TestGraphDeduplicatesImportsInDependencyOrder
import left from "./left.ms"
import right from "./right.ms"
fn result() Int: return left() + right()
