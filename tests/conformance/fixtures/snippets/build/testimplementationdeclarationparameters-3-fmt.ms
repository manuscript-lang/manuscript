// conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/build/compiler_test.go:520 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V

type Box[T]:
    value: T

fn Box[Int].get() Int:
    return self.value
