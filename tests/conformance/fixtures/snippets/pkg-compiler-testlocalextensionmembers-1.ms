# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:138 TestLocalExtensionMembers
export def read(value: Box[Int]) -> Int:
    return value.get()
