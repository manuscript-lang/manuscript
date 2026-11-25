// conform: tags=alternatives,diagnostics,formatter,lists,maps,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/checker_test.go:83 TestNestedCollectionsPreserveFiniteRecursiveApplications
type Value {
	children Map[String, Value]
}

type Wrapper {
	entries Map[String, Node]
}

enum Node {
	Leaf(value Value)
	Children(values List[Wrapper])
}
// expect-exit: 0
