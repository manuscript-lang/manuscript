# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:546 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Read[U] for Box[U]:
    fn get() U:
        return self.value
