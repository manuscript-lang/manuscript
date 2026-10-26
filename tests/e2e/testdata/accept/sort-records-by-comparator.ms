from "@std/collections.ms" import range
from "@std/testing.ms" import expect_equal

type Entry:
    key: Int
    id: Int

def entries(count: Int) -> List[Entry]:
    var out: List[Entry] = []
    var x = 7
    for i in range(0, count):
        x = (x * 1103515245 + 12345) % 2147483648
        out.append(Entry(key: x % 10, id: i))
    return out

test "sorting plain records by a comparator orders by key and keeps equal keys in input order":
    let sorted = entries(500).sorted(compare: lambda (a: Entry, b: Entry) -> Int: a.key - b.key)
    var ordered = True
    for i in range(1, sorted.length()):
        let before = sorted[i - 1]
        let after = sorted[i]
        if before.key > after.key or (before.key == after.key and before.id > after.id):
            ordered = False
    try expect_equal(ordered, True)
    try expect_equal(sorted.length(), 500)

test "sorting in place by a descending comparator reverses the key order":
    var list = entries(200)
    list.sort(compare: lambda (a: Entry, b: Entry) -> Int: b.key - a.key)
    var ordered = True
    for i in range(1, list.length()):
        if list[i - 1].key < list[i].key:
            ordered = False
    try expect_equal(ordered, True)
