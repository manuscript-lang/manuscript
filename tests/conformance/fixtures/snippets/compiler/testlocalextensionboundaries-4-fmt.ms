// conform: tags=formatter,parser,tier-core,scope-cleanup
// conform: phase=parse
// conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
fn use(value: Box[Int]) Unit:
    _resource := value
    return
