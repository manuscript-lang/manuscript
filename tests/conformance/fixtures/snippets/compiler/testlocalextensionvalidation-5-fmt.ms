# conform: tags=control-flow,formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:87 TestLocalExtensionValidation
impl Read[Int] for Int:
    fn get() Int:
        return self
