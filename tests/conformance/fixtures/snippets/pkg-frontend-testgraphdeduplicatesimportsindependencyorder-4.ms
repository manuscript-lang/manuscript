# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/frontend/source_test.go:31 TestGraphDeduplicatesImportsInDependencyOrder
from "./left.ms" import left
from "./right.ms" import right

def result() -> Int: return left() + right()
