type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

fn mirror(t: Tree) Tree:
    match t:
        Node(l, v):
            return Node(left: mirror(l), value: v)
        Leaf:
            return Leaf
