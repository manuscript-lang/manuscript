# conform: tags=alternatives,formatter,lists,maps,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/checker_test.go:83 TestNestedCollectionsPreserveFiniteRecursiveApplications
type Value:
    children: Map[String, Value]
type Wrapper:
    entries: Map[String, Node]
type Node:
    case Leaf(value: Value)
    case Children(values: List[Wrapper])
