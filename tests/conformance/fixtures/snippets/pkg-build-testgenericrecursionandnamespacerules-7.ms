# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
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
