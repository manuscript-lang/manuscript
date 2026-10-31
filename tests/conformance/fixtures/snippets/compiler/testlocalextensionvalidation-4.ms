# conform: tags=control-flow,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:83 TestLocalExtensionValidation
impl Read[Int] for Box[Int]:
    fn extra() Int:
        return 0
