# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:547 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Read[T] for Box[Int]:
    fn get() T:
        return self.value
