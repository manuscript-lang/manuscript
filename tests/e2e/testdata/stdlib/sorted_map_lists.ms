import (
    SortedMap from "@std/collections/sorted.ms",
    expect_equal from "@std/test/test.ms",
)

fn filled(count: Int) SortedMap[Int, String]:
    var map = SortedMap[Int, String]()

    // Insert from both ends so the chunks split in more than one place.
    for i in 0..count:
        key := if i % 2 == 0: i else: count * 2 - i
        map.add(key, "v{key}")

    return map

test "keys and values join every chunk in key order":
    for count in [0, 1, 2, 63, 64, 65, 129, 1000, 5000]:
        map := filled(count)
        keys := map.keys()
        values := map.values()
        try expect_equal(keys.length(), count)
        try expect_equal(values.length(), count)

        var previous = -1
        var index = 0

        while index < keys.length():
            try expect_equal(keys[index] > previous, true)
            try expect_equal(values[index], "v{keys[index]}")
            previous = keys[index]
            index += 1

test "keys returns an independent list":
    var map = filled(300)
    var keys = map.keys()
    keys.set(0, -5)
    try expect_equal(map.keys()[0], 0)
    map.add(-1, "extra")
    try expect_equal(keys.length(), 300)
