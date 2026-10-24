# conform: tags=control-flow,diagnostics,interfaces,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:79 TestLocalExtensionValidation
impl Read[Int] for Box[Int]:
    def get() -> String:
        return "wrong"
