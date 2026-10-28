# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:31 TestLocalExtensionBoundaries
fn use(value: Box[Int]) Read[Int]:
    return Read[Int](value: value)
