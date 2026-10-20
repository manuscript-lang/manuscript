# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:546 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Read[U] for Box[U]:
    fn get() U:
        return self.value
