# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:549 TestImplementationDeclarationParameters
interface Same[V: Equal]:
    def same(other: V) -> Bool

type Box[T]:
    value: T

impl Same[T] for Box[T]:
    def same(other: T) -> Bool:
        return self.value == other

def compare[T](value: Box[T], other: T) -> Bool:
    return value.same(other: other)
