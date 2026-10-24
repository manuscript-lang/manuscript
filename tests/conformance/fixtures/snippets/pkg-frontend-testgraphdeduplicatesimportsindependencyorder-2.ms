# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/frontend/source_test.go:29 TestGraphDeduplicatesImportsInDependencyOrder
from "./shared.ms" import value

export def left() -> Int: return value()
