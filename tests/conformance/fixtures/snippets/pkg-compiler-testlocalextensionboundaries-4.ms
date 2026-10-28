# conform: tags=diagnostics,tier-core,with-cleanup
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
fn use(value: Box[Int]) Unit:
    with let resource = value:
        return
