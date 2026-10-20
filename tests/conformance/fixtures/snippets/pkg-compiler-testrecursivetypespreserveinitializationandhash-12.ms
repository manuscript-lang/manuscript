# conform: tags=control-flow,diagnostics,generics,interfaces,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:21 TestRecursiveTypesPreserveInitializationAndHashing
interface I[T]:
    fn f(x: I[List[T]]) Int

type Box[T]:
    v: T
impl I[T] for Box[T]:
    fn f(x: I[List[T]]) Int:
        return 1
export fn main() Int:
    let b = Box[Int](v: 1)
    let i = I[Int](value: b)
    return 0
