# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:547 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Read[T] for Box[Int]:
    fn get() T:
        return self.value
