# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:31 TestLocalExtensionBoundaries
def use(value: Box[Int]) -> Read[Int]:
    return Read[Int](value: value)
