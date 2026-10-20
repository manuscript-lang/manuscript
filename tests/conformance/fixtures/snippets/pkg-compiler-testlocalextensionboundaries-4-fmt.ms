# conform: tags=formatter,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
fn use(value: Box[Int]) Unit:
    with resource = value:
        return
