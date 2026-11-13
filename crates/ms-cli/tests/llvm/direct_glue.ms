import stdout from "@std/io/io.ms"

type Item:
    label: String
    note: String?
    count: Int?

type Node:
    v: Int
    name: String
    next: Node?

type Bag:
    items: List[Item]
    grid: List[List[String]]
    raw: List[Int]

fn say(text: String) Unit:
    _ := stdout().write("{text}\n")

fn build(k: Int) Bag:
    var items: List[Item] = []
    var grid: List[List[String]] = []
    var raw: List[Int] = []
    for i in 0..k:
        note: String? := "a long note that does not fit inline {i}"
        items.append(Item(label: "label {i}", note: note, count: i))
        grid.append(["x{i}", "a long cell that does not fit inline {i}"])
        raw.append(i * 3)
    return Bag(items: items, grid: grid, raw: raw)

export fn main() Int:
    b := build(20)
    c := b.clone()
    d := c.clone()
    n := Node(v: 1, name: "first node name that is long enough", next: Node(v: 2, name: "second", next: Node(v: 3, name: "third node name long enough to heap", next: none)))
    m := n.clone()
    var total = 0
    for it in d.items:
        total += it.label.length()
        if it.count.is_some():
            total += 1
    for row in d.grid:
        total += row.length()
    say("{total} {d.raw.length()} {m.v} {m.name}")
    return 0
