// conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:262 TestGenericRecursionAndNamespaceRules
interface Read[T]:
    fn get() T

type Box[T]:
    value: T

fn Box[T].get() T:
    return self.value

fn Box[Int].get() Int:
    return self.value
