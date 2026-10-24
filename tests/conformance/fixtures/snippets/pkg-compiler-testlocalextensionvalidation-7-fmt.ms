# conform: tags=control-flow,formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:95 TestLocalExtensionValidation
impl Read[Int] for Read[Int]:
    def get() -> Int:
        return 0
