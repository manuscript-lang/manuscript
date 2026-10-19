type Tree:
    case Leaf
    case Node(left: Tree, value: Int)

fn sum(t: Tree) Int:
    match t:
        Node(l, v):
            return sum(l) + v
        Leaf:
            return 0
