// conform: tags=control-flow,diagnostics,faults,generics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:505 TestImplementationDeclarationParameters
interface Same[V: Equal]:
    fn same(other: V) Bool

interface Read[V]:
    fn get() V

type Box[T: Clonable]:
    value: T

fn Box[T: Equal].same(other: T) Bool:
    return self.value == other

fn Box[T].get() T:
    return self.value.clone()

fn read[T: Clonable](value: Box[T]) T:
    return value.get()
