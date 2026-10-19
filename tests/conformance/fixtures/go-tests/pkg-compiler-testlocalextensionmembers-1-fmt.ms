# conform: tags=faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:138 TestLocalExtensionMembers
export fn read(value: Box[Int]) Int:
    return value.get()
