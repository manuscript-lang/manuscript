# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:549 TestImplementationDeclarationParameters
interface Same[V: Equal]:
    fn same(other: V) Bool
type Box[T]:
    value: T
impl Same[T] for Box[T]:
    fn same(other: T) Bool:
        return self.value == other
fn compare[T](value: Box[T], other: T) Bool:
    return value.same(other: other)
