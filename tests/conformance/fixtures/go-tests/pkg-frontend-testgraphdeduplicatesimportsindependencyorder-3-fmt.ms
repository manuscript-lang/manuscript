# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/frontend/source_test.go:30 TestGraphDeduplicatesImportsInDependencyOrder
import value from "./shared.ms"
export fn right() Int: return value()
