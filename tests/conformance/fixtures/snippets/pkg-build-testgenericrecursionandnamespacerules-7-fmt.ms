# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:262 TestGenericRecursionAndNamespaceRules
interface Read[T]:
    def get() -> T

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    def get() -> T:
        return self.value

impl Read[Int] for Box[Int]:
    def get() -> Int:
        return self.value
