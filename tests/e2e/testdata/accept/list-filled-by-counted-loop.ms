from "@std/testing.ms" import expect_equal

def row(width: Int, seed: Int) -> List[Int]:
    var cells = List[Int]()
    cells.append(seed)

    var j = 0

    while j < width:
        if j % 2 == 0:
            cells.append(j)
        else:
            cells.append(-j)

        j = j + 1

    return cells

def table(n: Int) -> List[Int]:
    var prev = List[Int]()
    var j = 0

    while j <= n:
        prev.append(j)
        j = j + 1

    for k in [1, 2, 3]:
        var cur = List[Int]()
        j = 0

        while j < prev.length():
            cur.append(prev.get(j) + k)
            j = j + 1

        prev = cur

    return prev

test "lists filled by counted loops keep their items":
    row(5, 9) | try expect_equal([9, 0, -1, 2, -3, 4])
    row(0, 1) | try expect_equal([1])
    row(-4, 2) | try expect_equal([2])
    table(3) | try expect_equal([6, 7, 8, 9])
    table(-1) | try expect_equal(List[Int]())

test "a list grows past the reserved size":
    let wide = row(1100000, 0)
    wide.length() | try expect_equal(1100001)
    wide.get(1099999) | try expect_equal(1099998)
