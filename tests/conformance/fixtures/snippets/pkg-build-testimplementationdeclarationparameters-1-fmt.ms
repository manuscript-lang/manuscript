# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:495 TestImplementationDeclarationParameters
interface Same[V]:
    def same(other: V) -> Bool

type Box[T: Equal]:
    value: T

impl Same[T] for Box[T]:
    def same(other: T) -> Bool:
        return self.value == other

def compare[T: Equal](value: Box[T], other: T) -> Bool:
    return value.same(other: other)
