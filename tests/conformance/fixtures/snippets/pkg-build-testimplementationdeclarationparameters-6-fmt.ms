# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:547 TestImplementationDeclarationParameters
interface Read[V]:
    def get() -> V

type Box[T]:
    value: T

impl Read[T] for Box[Int]:
    def get() -> T:
        return self.value
