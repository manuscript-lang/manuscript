# conform: tags=optional,stdlib-sorted,stdlib-testing,testing,tier-stdlib
# conform: phase=test
import {expect_equal, expect_true, expect_false} from "@std/testing.ms"
import {SortedMap, SortedSet} from "@std/sorted.ms"
import {range} from "@std/collections.ms"

test "add get replace remove":
    var map = SortedMap[Int, String]()
    for key in [5, 1, 9, 3, 7]:
        map.add(key, "v{key}")
    try expect_equal(map.keys(), [1, 3, 5, 7, 9])
    try expect_equal(map.values(), ["v1", "v3", "v5", "v7", "v9"])
    try expect_equal(map.get(3), some("v3"))
    try expect_equal(map.get(4), none)
    map.add(3, "three")
    try expect_equal(map.get(3), some("three"))
    try expect_equal(map.length(), 5)
    map.remove(3)
    map.remove(100)
    try expect_false(map.contains(3))
    try expect_equal(map.length(), 4)

test "string keys order lexicographically":
    var map = SortedMap[String, Int]()
    for word in ["pear", "apple", "fig"]:
        map.add(word, word.length())
    try expect_equal(map.keys(), ["apple", "fig", "pear"])

test "first last floor ceiling and pops":
    var map = SortedMap[Int, Int]()
    for key in [10, 20, 30]:
        map.add(key, key * 2)
    try expect_equal(map.first().get().key, 10)
    try expect_equal(map.last().get().value, 60)
    try expect_equal(map.floor(25).get().key, 20)
    try expect_equal(map.floor(20).get().key, 20)
    try expect_equal(map.floor(5), none)
    try expect_equal(map.ceiling(25).get().key, 30)
    try expect_equal(map.ceiling(31), none)
    try expect_equal(map.pop_first().get().key, 10)
    try expect_equal(map.pop_last().get().key, 30)
    try expect_equal(map.keys(), [20])
    map.clear()
    try expect_equal(map.pop_first(), none)
    try expect_true(map.is_empty())

test "range is half open and spans chunks":
    var map = SortedMap[Int, Int]()
    for key in range(0, 3000):
        map.add(key * 2, key)
    let hits = map.range(1000, 1010)
    try expect_equal(hits.length(), 5)
    try expect_equal(hits.get(0).key, 1000)
    try expect_equal(hits.get(4).key, 1008)
    try expect_equal(map.range(0, 6000).length(), 3000)
    try expect_equal(map.range(5999, 7000).length(), 0)
    try expect_equal(map.range(10, 10).length(), 0)

test "many random operations agree with Map":
    var sorted = SortedMap[Int, Int]()
    var plain = Map[Int, Int]()
    var seed = 7

    for step in range(0, 20000):
        seed = (seed * 1103515245 + 12345) % 2147483648
        let key = seed % 2000

        if seed % 4 == 0:
            sorted.remove(key)
            plain.remove(key)
        else:
            sorted.add(key, step)
            plain.add(key, step)

    try expect_equal(sorted.length(), plain.length())
    var previous = -1

    for entry in sorted.entries():
        try expect_true(entry.key > previous)
        try expect_equal(plain.get(entry.key), some(entry.value))
        previous = entry.key

    for key in range(0, 2000):
        try expect_equal(sorted.contains(key), plain.contains(key))
        var expected: Optional[Int] = none
        for candidate in sorted.keys():
            if candidate <= key:
                expected = some(candidate)

        if let found = sorted.floor(key):
            try expect_equal(some(found.key), expected)
        else:
            try expect_equal(expected, none)

test "copies are independent":
    var a = SortedMap[Int, Int]()
    a.add(1, 1)
    var b = a.clone()
    b.add(2, 2)
    try expect_equal(a.keys(), [1])
    try expect_equal(b.keys(), [1, 2])

test "sorted set keeps unique ordered members":
    var set = SortedSet[Int]()
    for value in [4, 2, 4, 9, 1]:
        set.add(value)
    try expect_equal(set.values(), [1, 2, 4, 9])
    try expect_equal(set.length(), 4)
    try expect_true(set.contains(9))
    try expect_equal(set.first(), some(1))
    try expect_equal(set.last(), some(9))
    try expect_equal(set.floor(3), some(2))
    try expect_equal(set.ceiling(5), some(9))
    try expect_equal(set.range(2, 9), [2, 4])
    try expect_equal(set.pop_first(), some(1))
    try expect_equal(set.pop_last(), some(9))
    set.remove(4)
    set.remove(77)
    try expect_equal(set.values(), [2])
    set.clear()
    try expect_true(set.is_empty())
