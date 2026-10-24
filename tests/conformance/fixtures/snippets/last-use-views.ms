# conform: tags=strings,lists,maps,records,control-flow,stdlib-testing,testing,tier-core
# conform: phase=test
from "@std/testing.ms" import expect_equal
from "@std/collections.ms" import range

type Box:
    name: String
    items: List[Int]

impl Box:
    def label() -> ref String: self.name

    def all() -> ref List[Int]: self.items

# Churn that reuses freed memory, so a view of a value freed too early reads garbage.
def churn(n: Int) -> Int:
    var total = 0

    for i in range(0, n):
        let junk = f"junk-{i}-junk-{i}-junk-{i}"
        total += junk.length()

    return total

test "a trim view keeps its source until the view's last use":
    let source = "  hello, world  ".clone()
    let view = source.trim()
    let n = churn(200)
    try expect_equal(view, "hello, world")
    try expect_equal(n > 0, True)

test "a source whose last use is early is not needed by later work":
    let text = "alpha beta gamma".clone()
    let words = text.split(" ")
    let count = words.length()
    let n = churn(200)
    try expect_equal(count, 3)
    try expect_equal(n > 0, True)

test "a ref result borrows its argument until the result's last use":
    let box = Box(name: "boxed".clone(), items: [1, 2, 3])
    let label = box.label()
    let items = box.all()
    let n = churn(200)
    try expect_equal(label, "boxed")
    try expect_equal(items.length(), 3)
    try expect_equal(n > 0, True)

test "a view carried around a loop stays valid":
    let names = ["  a  ".clone(), " bb ".clone(), "ccc".clone()]
    var longest = ""
    var total = 0

    for name in names:
        let view = name.trim()
        total += churn(20)
        if view.length() > longest.length():
            longest = view.clone()

    try expect_equal(longest, "ccc")
    try expect_equal(total > 0, True)

test "a value used only inside one branch is freed on the other path":
    let data = [10, 20, 30]
    var sum = 0

    for i in range(0, 4):
        if i % 2 == 0:
            sum += data[0]
        else:
            sum += churn(5)

    try expect_equal(sum > 20, True)

test "map keys read after the map's earlier uses stay valid":
    var m = Map[String, Int]()
    m.add("one".clone(), 1)
    m.add("two".clone(), 2)

    let size = m.length()
    var seen = 0
    for k in m.keys():
        seen += k.length()

    let n = churn(100)
    try expect_equal(size, 2)
    try expect_equal(seen, 6)
    try expect_equal(n > 0, True)
