type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

fn f(var t: Tree) Tree:
    match t:
        Node(l, v):
            return l
        Leaf:
            return Leaf  # error: returns a reference into its arguments
