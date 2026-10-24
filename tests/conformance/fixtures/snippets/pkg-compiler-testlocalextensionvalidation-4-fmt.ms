# conform: tags=control-flow,formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:83 TestLocalExtensionValidation
impl Read[Int] for Box[Int]:
    def extra() -> Int:
        return 0
