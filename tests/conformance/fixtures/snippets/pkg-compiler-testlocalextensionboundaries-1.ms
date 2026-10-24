# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:28 TestLocalExtensionBoundaries
def use(value: Box[Int]) -> Int:
    return value.get()
