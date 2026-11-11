// conform: tags=diagnostics
// conform: phase=check
type Value:
    children: Map[String, Value]
type Wrapper:
    entries: Map[String, Node]
enum Node:
    Leaf(value: Value)
    Children(values: List[Wrapper])
