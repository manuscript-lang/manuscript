type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

def mirror(t: Tree) -> Tree:
    match t:
        case Node(l, v):
            return Node(left: mirror(l), value: v)
        case Leaf:
            return Leaf
