type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

fn f(var t: Tree) Int:
    match t:
        Node(l, v):
            t = Leaf  # error: while `l` borrows it
            return v
        Leaf:
            return 0
