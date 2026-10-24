type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

def f(var t: Tree) -> Tree:
    match t:
        case Node(l, v):
            return l  # error: only borrows its value
        case Leaf:
            return Leaf
