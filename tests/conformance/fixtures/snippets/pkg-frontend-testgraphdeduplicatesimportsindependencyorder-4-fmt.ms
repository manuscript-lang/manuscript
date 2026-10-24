# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/frontend/source_test.go:31 TestGraphDeduplicatesImportsInDependencyOrder
from "./left.ms" import left
from "./right.ms" import right

def result() -> Int: return left() + right()
