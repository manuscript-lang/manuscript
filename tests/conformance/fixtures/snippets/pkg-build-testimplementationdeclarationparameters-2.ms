# conform: tags=control-flow,diagnostics,faults,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:505 TestImplementationDeclarationParameters
interface Same[V: Equal]:
    def same(other: V) -> Bool

interface Read[V]:
    def get() -> ref V

type Box[T]:
    value: T

impl Same[T] for Box[T]:
    def same(other: T) -> Bool:
        return self.value == other

impl Read[T] for Box[T]:
    def get() -> ref T:
        return self.value

def read[T](value: Box[T]) -> ref T:
    return value.get()
