# conform: tags=control-flow,formatter,interfaces,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:91 TestLocalExtensionValidation
impl Read[Int] for List[Int]:
    fn get() Int:
        return 0
