# conform: tags=control-flow,formatter,generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:75 TestLocalExtensionValidation
impl Read[T] for Box[T]:
    fn get() T:
        return missing
