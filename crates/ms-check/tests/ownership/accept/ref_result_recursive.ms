type Node:
    name: String
    children: List[Node]

# A recursive `ref` function lends from the arguments its other paths lend from: here only the
# node, so the temporary list and the computed index need not outlive the call.
fn find(node: Node, path: List[String], from: Int) ref Optional[Node]:
    if from >= path.length(): return none

    for child in node.children:
        if child.name == path[from]:
            if from == path.length() - 1: return some(child)

            return find(child, path, from + 1)

    return none

fn name_at(root: Node) ref Optional[String]:
    if let n = find(root, ["a", "b"], 0):
        return some(n.name)

    return none
