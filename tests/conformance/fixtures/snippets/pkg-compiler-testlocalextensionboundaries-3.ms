# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:34 TestLocalExtensionBoundaries
from "./domain.ms" import invoke

def use(value: Box[Int]) -> Int:
    return invoke(value)
