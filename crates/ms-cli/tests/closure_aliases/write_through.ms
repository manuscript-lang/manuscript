import stdout from "@std/io/io.ms"

fn invoke(f: fn() Void) Void:
    f()

type Box:
    count: Int
    items: List[List[Int]]

type Pair:
    left: List[Int]
    right: List[Int]

fn var Box.bump() Void:
    self.count += 1

fn add(var values: List[Int]) Void:
    values.append(12)

fn next(var count: Int) Int:
    result := count
    count += 1
    return result

fn branch(var box: Box, take: Bool) Void:
    if take:
        // A scalar `var` copies, so the closure changes the copy, not `box.count`.
        var _count = box.count
        invoke(fn: _count += 3)

    box.count += 1

fn main() Void:
    var calls = 0
    var rows = [[1], [2]]
    var first = rows[next(calls)]
    append := fn: first.append(9)
    append()
    append()

    void stdout().write(f"{calls} {rows}\n")
    var box = Box(count: 1, items: [[3], [4]])
    branch(box, false)
    branch(box, true)

    void stdout().write(f"{box.count}\n")
    var items = box.items
    var inner = items[1]
    invoke(fn: invoke(fn: inner.append(8)))

    void stdout().write(f"{box.items}\n")
    var entries = Map[String, List[Int]]()
    entries.add("dynamic-1", [5])
    if var value = entries[f"dynamic-{calls}"]?:
        invoke(fn: value.append(value.length()))

    void stdout().write(f"{entries}\n")
    var pair = Pair(left: [1], right: [2])
    var left = pair.left
    var right = pair.right

    invoke(
        fn:
            left.append(3)
            right.append(4)
    )

    void stdout().write(f"{pair}\n")
    var local_rows = [[10]]

    invoke(
        fn:
            var local = local_rows[0]
            invoke(fn: local.append(11))
    )

    void stdout().write(f"{local_rows}\n")
    var boxes = [Box(count: 20, items: [])]
    var stored = boxes[0]
    invoke(fn: stored.bump())

    void stdout().write(f"{boxes}\n")
    var target = rows[1]
    invoke(fn: add(target))

    void stdout().write(f"{rows}\n")
