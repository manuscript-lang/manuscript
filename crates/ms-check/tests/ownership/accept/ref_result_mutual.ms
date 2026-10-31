type Node:
    name: String
    children: List[Node]

# `g` is walked before `f`, whose summary it needs: its path through `f` still lends.
fn g(a: Node, i: Int) ref Node?:
    return f(a, i)

fn f(a: Node, i: Int) ref Node?:
    if i == 0: return a.children[0]

    return g(a, i - 1)

# A cycle of three, where only one function has a path of its own.
fn c1(a: Node, i: Int) ref Node?:
    return c2(a, i)

fn c2(a: Node, i: Int) ref Node?:
    return c3(a, i)

fn c3(a: Node, i: Int) ref Node?:
    if i == 0: return a.children[0]

    return c1(a, i - 1)

fn name_of(a: Node) ref String?:
    if let n = g(a, 3):
        return n.name
    if let m = c1(a, 2):
        return m.name

    return none
