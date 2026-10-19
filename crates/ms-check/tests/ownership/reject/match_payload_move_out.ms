type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

fn f(var t: Tree) Tree:
    match t:
        Node(l, v):
            return l  # error: only borrows its value
        Leaf:
            return Leaf
