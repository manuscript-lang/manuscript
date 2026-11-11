// conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/build/compiler_test.go:262 TestGenericRecursionAndNamespaceRules
interface Read[T]:
    fn get() T

type Box[T]:
    value: T

fn Box[T].get() T:
    return self.value

fn Box[Int].get() Int:
    return self.value
