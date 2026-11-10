type Node:
    args: List[Node] = []

export fn main() Int:
    m := Map[Int, Node]()
    return m.get_or(1, Node()).args.length()
