# conform: tags=control-flow,formatter,interfaces,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:79 TestLocalExtensionValidation
impl Read[Int] for Box[Int]:
    fn get() String:
        return "wrong"
