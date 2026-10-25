type Node:
    name: String
    children: List[Node]

# The recursive call lends from its node argument, which is a copy made for the call.
def find(node: Node, from: Int) -> ref Optional[Node]:
    if from == 0: return some(node.children[0])

    return find(node.clone(), from - 1)  # error: gives back an owned value
