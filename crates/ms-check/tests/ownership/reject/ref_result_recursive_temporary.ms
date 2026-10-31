type Node:
    name: String
    children: List[Node]

# The recursive call lends from its node argument, which is a copy made for the call.
fn find(node: Node, from: Int) ref Node?:
    if from == 0: return node.children[0]

    return find(node.clone(), from - 1)  # error: gives back an owned value
