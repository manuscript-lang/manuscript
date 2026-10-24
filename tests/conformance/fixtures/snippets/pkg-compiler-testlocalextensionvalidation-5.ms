# conform: tags=control-flow,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:87 TestLocalExtensionValidation
impl Read[Int] for Int:
    def get() -> Int:
        return self
