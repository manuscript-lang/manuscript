# conform: tags=formatter,parser,tier-core,scope-cleanup
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
def use(value: Box[Int]) -> Unit:
    let _resource = value
    return
