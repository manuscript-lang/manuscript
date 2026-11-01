# conform: tags=control-flow,lists,maps,modules,mutation,records,stdlib-testing,testing,tier-core
# conform: phase=test
# conform: origin=bug bash: lowering and codegen
import expect_equal from "@std/test/test.ms"

type Pt:
    x: Int
    y: Int

type Row:
    cells: List[Int]
    pt: Pt

fn shift(var p: Pt, dx: Int) Unit:
    p.x += dx

fn shift_at(var pts: List[Pt], i: Int, dx: Int) Unit:
    shift(var pts[i], dx)

fn grow(var rows: List[Row], i: Int, j: Int) Unit:
    rows[i].cells.append(j)
    rows[i].pt.y = j

test "a var argument rooted at an element with a variable index writes back":
    var pts = [Pt(0, 0), Pt(1, 1)]
    shift_at(var pts, 1, 5)
    try expect_equal(pts[1].x, 6)
    try expect_equal(pts[0].x, 0)
    for i in 0..2:
        shift(var pts[i], 10)
    try expect_equal(pts[0].x, 10)
    try expect_equal(pts[1].x, 16)

test "field assignment and mutators through a variable element index":
    var rows = [Row([1], Pt(0, 0)), Row([], Pt(5, 5))]
    for i in 0..2:
        grow(var rows, i, i + 10)
    try expect_equal(rows[0].cells, [1, 10])
    try expect_equal(rows[1].cells, [11])
    try expect_equal(rows[1].pt.y, 11)

    let k = 1
    var pts = [Pt(1, 1), Pt(2, 2)]
    pts[k].x = 9
    pts[k - 1].y = 4
    try expect_equal(pts[1].x, 9)
    try expect_equal(pts[0].y, 4)

test "an eager get_or fallback is released when the key is present":
    var m = Map[String, List[Int]]()
    m.add(key: "k", value: [1, 2])

    var got = m.get_or(key: "k", fallback: List[Int]()).clone()
    got.append(3)
    try expect_equal(got, [1, 2, 3])
    try expect_equal(m.get_or(key: "k", fallback: List[Int]()), [1, 2])
    try expect_equal(m.get_or(key: "absent", fallback: [7]), [7])

test "an eager list get default is released on every path":
    let xs = [[1, 2], [3]]
    try expect_equal(xs.get(0, default: [9, 9]), [1, 2])
    try expect_equal(xs.get(5, default: [9, 9]), [9, 9])
    try expect_equal(xs.get(-1, default: [9, 9]), [3])

    let words = "a,b".split(",")
    try expect_equal(words.get(1, default: "z" + "z"), "b")
    try expect_equal(words.get(8, default: "z" + "z"), "zz")

test "find over owned elements keeps the hit":
    let rows = [[1], [2], [3, 3]]
    try expect_equal(rows.find(fn(value: List[Int]): value[0] == 2), [2])
    try expect_equal(rows.find(fn(value: List[Int]): value[0] == 9), none)
    try expect_equal(rows.find_last(fn(value: List[Int]): value[0] > 1), [3, 3])
