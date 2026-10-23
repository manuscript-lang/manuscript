import stdout from "@std/io.ms"

fn invoke(f: fn() Unit) Unit:
    f()

type Box:
    count: Int
    items: List[List[Int]]

type Pair:
    left: List[Int]
    right: List[Int]

fn next(var count: Int) Int:
    let result = count

    count += 1
    return result

fn branch(var box: Box, take: Bool) Unit:
    if take:
        var count = box.count

        invoke(fn(): count += 3)

    box.count += 1

fn contents(box: Box) List[List[Int]]:
    return box.items

export fn main() Int:
    var calls = 0
    var rows = [[1], [2]]
    var first = rows[next(var calls)]
    let append = fn(): first.append(9)

    append()
    append()
    stdout().write("{calls} {rows}\n")

    var box = Box(count: 1, items: [[3], [4]])

    branch(var box, false)
    branch(var box, true)
    stdout().write("{box.count}\n")

    var items = box.items
    var inner = items[1]

    invoke(fn(): invoke(fn(): inner.append(8)))
    stdout().write("{box.items}\n")

    var entries = Map[String, List[Int]]()

    entries.add("dynamic-1", [5])
    if var value = entries.get("dynamic-{calls}"):
        invoke(fn(): value.append(value.length()))
    stdout().write("{entries}\n")

    var pair = Pair(left: [1], right: [2])
    var left = pair.left
    var right = pair.right

    invoke(
        fn():
            left.append(3)
            right.append(4)
    )
    stdout().write("{pair}\n")

    var local_rows = [[10]]

    invoke(
        fn():
            var local = local_rows[0]

            invoke(fn(): local.append(11))
    )
    stdout().write("{local_rows}\n")

    var via_getter = contents(box)

    invoke(fn(): via_getter.append([6]))
    stdout().write("{box.items}\n")
    return 0
