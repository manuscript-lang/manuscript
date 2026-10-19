# conform: tags=control-flow,faults,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:505 TestImplementationDeclarationParameters
interface Same[V: Equal]:
    fn same(other: V) Bool
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Same[T] for Box[T]:
    fn same(other: T) Bool:
        return self.value == other
impl Read[T] for Box[T]:
    fn get() T:
        return self.value
fn read[T](value: Box[T]) T:
    return value.get()
