# conform: tags=diagnostics,tier-core,with-cleanup
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
def use(value: Box[Int]) -> Unit:
    let _resource = value
    return
