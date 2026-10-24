from "@std/io.ms" import stdout

type Box:
    items: List[Int]
    name: String

def early(var rows: List[List[Int]], c: Bool) -> Unit:
    var x = rows[0]
    x.append(1)
    if c:
        return

    x.append(2)

def in_loop(var rows: List[List[Int]]) -> Unit:
    for i in [0, 1, 2]:
        var x = rows[i]
        if i == 1:
            continue
        if i == 2:
            break

        x.append(100 + i)

def failing(var rows: List[List[Int]], bad: Bool) -> Int:
    var x = rows[1]
    x.append(7)
    if bad:
        return 0

    x.append(8)
    return 1

def generic[T](var xs: List[List[T]], v: T) -> Unit:
    var x = xs[0]
    x.append(v)

def nested(var boxes: List[Box]) -> Unit:
    var b = boxes[1]
    var it = b.items
    it.append(42)
    b.name = "renamed"

def moving_index(var rows: List[List[Int]]) -> Unit:
    var i = 0
    var x = rows[i]
    i = i + 1
    x.append(55)
    rows.append([i])

export def main() -> Int:
    var a = [[0], [0]]
    early(var a, True)
    early(var a, False)

    var b = [[0], [0], [0]]
    in_loop(var b)

    var c = [[0], [0]]
    let r1 = failing(var c, True)
    let r2 = failing(var c, False)
    var d = [["a"], ["b"]]
    generic(var d, "z")

    var e = [[1], [2]]
    generic(var e, 9)

    var boxes = [Box(items: [], name: "p"), Box(items: [1], name: "q")]
    nested(var boxes)

    var f = [[0], [0]]
    moving_index(var f)
    stdout().write(f"{a}\n{b}\n{c}\n{d}\n{e}\n{boxes}\n{f}\n").get()
    return 0
