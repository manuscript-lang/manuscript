# conform: tags=control-flow,formatter,generics,interfaces,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:21 TestRecursiveTypesPreserveInitializationAndHashing
interface I[T]:
    def f(x: I[List[T]]) -> Int

type Box[T]:
    v: T

impl I[T] for Box[T]:
    def f(x: I[List[T]]) -> Int:
        return 1

export def main() -> Int:
    let b = Box[Int](v: 1)
    let i = I[Int](value: b)
    return 0
