# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:495 TestImplementationDeclarationParameters
interface Same[V]:
    fn same(other: V) Bool

type Box[T: Equal]:
    value: T

impl Same[T] for Box[T]:
    fn same(other: T) Bool:
        return self.value == other

fn compare[T: Equal](value: Box[T], other: T) Bool:
    return value.same(other: other)
