# conform: tags=diagnostics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:19 TestRecursiveTypesPreserveInitializationAndHashing
type B[T]:
    a: A[List[T]]
type A[T]:
    b: B[T]
type C[T]:
    b: B[T]
