# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:34 TestLocalExtensionBoundaries
from "./domain.ms" import invoke

def use(value: Box[Int]) -> Int:
    return invoke(value)
