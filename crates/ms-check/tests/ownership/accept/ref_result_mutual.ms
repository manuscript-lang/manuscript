type Node:
    name: String
    children: List[Node]

# `g` is walked before `f`, whose summary it needs: its path through `f` still lends.
def g(a: Node, i: Int) -> ref Optional[Node]:
    return f(a, i)

def f(a: Node, i: Int) -> ref Optional[Node]:
    if i == 0: return some(a.children[0])
    return g(a, i - 1)

# A cycle of three, where only one function has a path of its own.
def c1(a: Node, i: Int) -> ref Optional[Node]:
    return c2(a, i)

def c2(a: Node, i: Int) -> ref Optional[Node]:
    return c3(a, i)

def c3(a: Node, i: Int) -> ref Optional[Node]:
    if i == 0: return some(a.children[0])
    return c1(a, i - 1)

def name_of(a: Node) -> ref Optional[String]:
    if let n = g(a, 3):
        return some(n.name)
    if let m = c1(a, 2):
        return some(m.name)
    return none
