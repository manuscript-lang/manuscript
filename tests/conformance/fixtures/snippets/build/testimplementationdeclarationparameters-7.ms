// conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:548 TestImplementationDeclarationParameters
interface Read:
    fn get() Int

type Box[T]:
    value: T

fn Box[Int].get() T:
    return self.value
