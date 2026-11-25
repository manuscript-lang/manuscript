// conform: tags=diagnostics,formatter,generics,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/recursive_types_test.go:49 TestRecursiveTypesPreserveInitializationAndHashing
type Box[T] {
	value T
}

fn hash(box Box[Box[Int]]) Int => return box.hash()
// expect-exit: 0
