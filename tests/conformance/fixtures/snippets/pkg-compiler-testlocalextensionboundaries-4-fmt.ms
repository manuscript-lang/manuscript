# conform: tags=formatter,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
def use(value: Box[Int]) -> Unit:
    with let resource = value:
        return
