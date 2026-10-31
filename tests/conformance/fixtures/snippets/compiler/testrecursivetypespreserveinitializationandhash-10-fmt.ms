# conform: tags=formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:19 TestRecursiveTypesPreserveInitializationAndHashing
type B[T]:
    a: A[List[T]]

type A[T]:
    b: B[T]

type C[T]:
    b: B[T]
