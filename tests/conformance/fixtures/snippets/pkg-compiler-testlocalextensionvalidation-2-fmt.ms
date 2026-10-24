# conform: tags=control-flow,formatter,generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:75 TestLocalExtensionValidation
impl Read[T] for Box[T]:
    def get() -> T:
        return missing
