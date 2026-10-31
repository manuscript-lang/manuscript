# conform: tags=diagnostics,tier-core,scope-cleanup
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
fn use(value: Box[Int]) Unit:
    let _resource = value
    return
