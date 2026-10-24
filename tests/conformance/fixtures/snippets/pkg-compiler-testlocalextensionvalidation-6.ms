# conform: tags=control-flow,diagnostics,interfaces,lists,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:91 TestLocalExtensionValidation
impl Read[Int] for List[Int]:
    def get() -> Int:
        return 0
