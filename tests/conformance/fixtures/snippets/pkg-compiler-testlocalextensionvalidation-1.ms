# conform: tags=control-flow,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:70 TestLocalExtensionValidation
impl Read[Int] for Box[Int]:
    def get() -> Int:
        return 0
