# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/frontend/source_test.go:30 TestGraphDeduplicatesImportsInDependencyOrder
from "./shared.ms" import value

export def right() -> Int: return value()
