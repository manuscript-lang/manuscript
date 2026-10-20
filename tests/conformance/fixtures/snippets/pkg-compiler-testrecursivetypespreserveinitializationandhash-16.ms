# conform: tags=diagnostics,generics,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:49 TestRecursiveTypesPreserveInitializationAndHashing
type Box[T]:
    value: T
fn hash(box: Box[Box[Int]]) Int: return box.hash()
