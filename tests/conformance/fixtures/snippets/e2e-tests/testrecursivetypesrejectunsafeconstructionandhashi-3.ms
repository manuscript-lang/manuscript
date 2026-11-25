// conform: tags=closures,diagnostics,generics,lists,records,tier-core
// conform: phase=check
// conform: origin=tests/e2e/recursive_types_test.go:14 TestRecursiveTypesRejectUnsafeConstructionAndHashing
type Grow[T] {
	next fn() Grow[List[T]]
}

export fn main() Int => return 0
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters in Grow.next; keep the same type arguments in the same positions along a recursive cycle
