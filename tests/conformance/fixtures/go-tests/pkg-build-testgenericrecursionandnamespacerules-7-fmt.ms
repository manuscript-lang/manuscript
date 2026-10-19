# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:262 TestGenericRecursionAndNamespaceRules
interface Read[T]:
    fn get() T
type Box[T]:
    value: T
impl Read[T] for Box[T]:
    fn get() T:
        return self.value
impl Read[Int] for Box[Int]:
    fn get() Int:
        return self.value
