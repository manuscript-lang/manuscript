type Node:
    name: String
    children: List[Node]

# Only the last function lends from `q`; the fact must travel back up the whole chain, which takes
# more summary rounds than a fixed cap allowed.

fn c1(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c2(p, q, i - 1)

fn c2(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c3(p, q, i - 1)

fn c3(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c4(p, q, i - 1)

fn c4(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c5(p, q, i - 1)

fn c5(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c6(p, q, i - 1)

fn c6(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c7(p, q, i - 1)

fn c7(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c8(p, q, i - 1)

fn c8(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c9(p, q, i - 1)

fn c9(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c10(p, q, i - 1)

fn c10(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c11(p, q, i - 1)

fn c11(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c12(p, q, i - 1)

fn c12(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c13(p, q, i - 1)

fn c13(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c14(p, q, i - 1)

fn c14(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c15(p, q, i - 1)

fn c15(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c16(p, q, i - 1)

fn c16(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c17(p, q, i - 1)

fn c17(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c18(p, q, i - 1)

fn c18(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c19(p, q, i - 1)

fn c19(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return c20(p, q, i - 1)

fn c20(p: Node, q: Node, i: Int) ref Node?:
    if i == 0: return some(p.children[0])

    return some(q.children[0])

fn reader(n: Node, var m: Node) Int:
    let r = c1(n, m, 20)
    m = Node(name: "other", children: [])  # error: cannot reassign `m` while `r` borrows it
    return r.get().children.length()
