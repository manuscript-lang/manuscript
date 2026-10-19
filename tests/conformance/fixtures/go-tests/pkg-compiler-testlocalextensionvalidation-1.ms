# conform: tags=control-flow,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:70 TestLocalExtensionValidation
impl Read[Int] for Box[Int]:
    fn get() Int:
        return 0
