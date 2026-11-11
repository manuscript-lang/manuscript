// conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:520 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V

type Box[T]:
    value: T

fn Box[Int].get() Int:
    return self.value
