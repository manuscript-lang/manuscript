import expect_equal from "@std/test/test.ms"

type Entry:
    key: Int
    id: Int

fn entries(count: Int) List[Entry]:
    var out: List[Entry] = []
    var x = 7

    for i in 0..count:
        x = (x * 1103515245 + 12345) % 2147483648
        out.append(Entry(key: x % 10, id: i))

    return out

test "sorting plain records by a comparator orders by key and keeps equal keys in input order":
    let sorted = entries(500).sorted(
        compare: fn(a: Entry, b: Entry) Int: (a.key - b.key)
    )
    var ordered = true

    for i in 1..sorted.length():
        let before = sorted[i - 1]
        let after = sorted[i]
        if before.key > after.key or (before.key == after.key and before.id > after.id):
            ordered = false

    try expect_equal(ordered, true)
    try expect_equal(sorted.length(), 500)

test "sorting in place by a descending comparator reverses the key order":
    var list = entries(200)
    list.sort(compare: fn(a: Entry, b: Entry) Int: b.key - a.key)

    var ordered = true
    for i in 1..list.length():
        if list[i - 1].key < list[i].key:
            ordered = false
    try expect_equal(ordered, true)

fn shaped(count: Int, shape: Int) List[Entry]:
    var out: List[Entry] = []

    for i in 0..count:
        if shape == 0:
            out.append(Entry(key: i / 7, id: i))
        else if shape == 1:
            out.append(Entry(key: (count - i) / 7, id: i))
        else:
            out.append(Entry(key: (i % 2) * 3 + i / 50, id: i))

    return out

test "ascending, descending and interleaved inputs sort stably at every size":
    for shape in 0..3:
        for count in [0, 1, 2, 3, 12, 13, 24, 25, 100, 127, 128, 129, 1000]:
            let sorted = shaped(count, shape).sorted(
                compare: fn(a: Entry, b: Entry) Int: (a.key - b.key)
            )
            var ordered = true
            var seen = 0

            for i in 0..sorted.length():
                seen += sorted[i].id

                if i > 0:
                    let before = sorted[i - 1]
                    let after = sorted[i]
                    if (
                        before.key > after.key
                        or (
                            before.key == after.key
                            and before.id > after.id
                        )
                    ):
                        ordered = false

            try expect_equal(ordered, true)
            try expect_equal(sorted.length(), count)
            try expect_equal(seen, count * (count - 1) / 2)
