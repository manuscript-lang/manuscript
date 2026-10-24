type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

def sum(t: Tree) -> Int:
    match t:
        case Node(l, v):
            return sum(l) + v
        case Leaf:
            return 0
