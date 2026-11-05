// conform: tags=alternatives,diagnostics,lists,maps,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/checker/checker_test.go:83 TestNestedCollectionsPreserveFiniteRecursiveApplications
type Value:
    children: Map[String, Value]

type Wrapper:
    entries: Map[String, Node]

enum Node:
    Leaf(value: Value)
    Children(values: List[Wrapper])
