type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

def f(var t: Tree) -> Int:
    match t:
        case Node(l, v):
            t = Leaf  # error: while `l` borrows it
            return v
        case Leaf:
            return 0
