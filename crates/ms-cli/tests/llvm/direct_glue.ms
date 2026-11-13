import stdout from "@std/io/io.ms"

type P:
    name: String
    tags: List[String]
    n: Int

type Node:
    v: Int
    next: Node?

fn say(text: String) Unit:
    _ := stdout().write("{text}\n")

export fn main() Int:
    var ps: List[P] = []
    for i in 0..50:
        ps.append(P(name: "item number {i}", tags: ["a", "bb{i}"], n: i))
    c := ps.clone()
    o: String? := "hello world this is long text"
    o2 := o.clone()
    var total = 0
    for p in c:
        total += p.n + p.tags.length()
    n := Node(v: 1, next: Node(v: 2, next: none))
    m := n.clone()
    say("{total} {o2} {m.v}")
    return 0
