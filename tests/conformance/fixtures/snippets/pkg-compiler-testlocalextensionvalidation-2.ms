# conform: tags=control-flow,diagnostics,generics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:75 TestLocalExtensionValidation
impl Read[T] for Box[T]:
    fn get() T:
        return missing
