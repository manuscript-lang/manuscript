from "@std/io.ms" import stdout

def invoke(f: Callable[[], Unit]) -> Unit:
    f()

type Box:
    count: Int
    items: List[List[Int]]

type Pair:
    left: List[Int]
    right: List[Int]

impl Box:
    var def bump() -> Unit:
        self.count += 1

def add(var values: List[Int]) -> Unit:
    values.append(12)

def next(var count: Int) -> Int:
    let result = count
    count += 1
    return result

def branch(var box: Box, take: Bool) -> Unit:
    if take:
        var _count = box.count
        invoke(lambda: _count += 3)

    box.count += 1

def contents(box: Box) -> ref List[List[Int]]:
    return box.items

export def main() -> Int:
    var calls = 0
    var rows = [[1], [2]]
    var first = rows[next(var calls)]
    let append = lambda: first.append(9)
    append()
    append()
    stdout().write(f"{calls} {rows}\n")

    var box = Box(count: 1, items: [[3], [4]])
    branch(var box, False)
    branch(var box, True)
    stdout().write(f"{box.count}\n")

    var items = box.items
    var inner = items[1]
    invoke(lambda: invoke(lambda: inner.append(8)))
    stdout().write(f"{box.items}\n")

    var entries = Map[String, List[Int]]()
    entries.add("dynamic-1", [5])
    if var value = entries.get(f"dynamic-{calls}"):
        invoke(lambda: value.append(value.length()))
    stdout().write(f"{entries}\n")

    var pair = Pair(left: [1], right: [2])
    var left = pair.left
    var right = pair.right

    invoke(
        lambda:
            left.append(3)
            right.append(4)
    )

    stdout().write(f"{pair}\n")

    var local_rows = [[10]]

    invoke(
        lambda:
            var local = local_rows[0]
            invoke(lambda: local.append(11))
    )

    stdout().write(f"{local_rows}\n")

    var via_getter = contents(box)
    invoke(lambda: via_getter.append([6]))
    stdout().write(f"{box.items}\n")

    var boxes = [Box(count: 20, items: [])]
    var stored = boxes[0]
    invoke(lambda: stored.bump())
    stdout().write(f"{boxes}\n")

    var target = rows[1]
    invoke(lambda: add(var target))
    stdout().write(f"{rows}\n")
    return 0
