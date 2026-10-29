# conform: tags=control-flow,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:95 TestLocalExtensionValidation
impl Read[Int] for Read[Int]:
    fn get() Int:
        return 0
