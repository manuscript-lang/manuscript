// conform: tags=optional,stdlib-sorted,stdlib-testing,testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true, expect_false from "@std/test/test.ms"
import SortedMap, SortedSet from "@std/collections/sorted.ms"

test "add get replace remove":
    var map = SortedMap[Int, String]()
    for key in [5, 1, 9, 3, 7]:
        map.add(key, "v{key}")
    expect_equal(map.keys(), [1, 3, 5, 7, 9])?
    expect_equal(map.values(), ["v1", "v3", "v5", "v7", "v9"])?
    expect_equal(map.get(3), "v3")?
    expect_equal(map.get(4), none)?
    map.add(3, "three")
    expect_equal(map.get(3), "three")?
    expect_equal(map.length(), 5)?
    map.remove(3)
    map.remove(100)
    expect_false(map.contains(3))?
    expect_equal(map.length(), 4)?

test "string keys order lexicographically":
    var map = SortedMap[String, Int]()

    for word in ["pear", "apple", "fig"]:
        size := word.length()
        map.add(word, size)

    expect_equal(map.keys(), ["apple", "fig", "pear"])?

test "first last floor ceiling and pops":
    var map = SortedMap[Int, Int]()
    for key in [10, 20, 30]:
        map.add(key, key * 2)
    expect_equal(map.first().get().key, 10)?
    expect_equal(map.last().get().value, 60)?
    expect_equal(map.floor(25).get().key, 20)?
    expect_equal(map.floor(20).get().key, 20)?
    expect_equal(map.floor(5), none)?
    expect_equal(map.ceiling(25).get().key, 30)?
    expect_equal(map.ceiling(31), none)?
    expect_equal(map.pop_first().get().key, 10)?
    expect_equal(map.pop_last().get().key, 30)?
    expect_equal(map.keys(), [20])?
    map.clear()
    expect_equal(map.pop_first(), none)?
    expect_true(map.is_empty())?

test "range is half open and spans chunks":
    var map = SortedMap[Int, Int]()
    for key in 0..3000:
        map.add(key * 2, key)

    hits := map.range(1000, 1010)
    expect_equal(hits.length(), 5)?
    expect_equal(hits.get(0).key, 1000)?
    expect_equal(hits.get(4).key, 1008)?
    expect_equal(map.range(0, 6000).length(), 3000)?
    expect_equal(map.range(5999, 7000).length(), 0)?
    expect_equal(map.range(10, 10).length(), 0)?

test "many random operations agree with Map":
    var sorted = SortedMap[Int, Int]()
    var plain = Map[Int, Int]()
    var seed = 7

    for step in 0..20000:
        seed = (seed * 1103515245 + 12345) % 2147483648

        key := seed % 2000

        if seed % 4 == 0:
            sorted.remove(key)
            plain.remove(key)
        else:
            sorted.add(key, step)
            plain.add(key, step)

    expect_equal(sorted.length(), plain.length())?

    var previous = -1

    for entry in sorted.entries():
        expect_true(entry.key > previous)?
        expect_equal(plain.get(entry.key), entry.value)?
        previous = entry.key

    for key in 0..2000:
        expect_equal(sorted.contains(key), plain.contains(key))?

        var expected: Int? = none
        for candidate in sorted.keys():
            if candidate <= key:
                expected = candidate

        if found := sorted.floor(key):
            expect_equal(found.key, expected)?
        else:
            expect_equal(expected, none)?

test "copies are independent":
    var a = SortedMap[Int, Int]()
    a.add(1, 1)

    var b = a.clone()
    b.add(2, 2)
    expect_equal(a.keys(), [1])?
    expect_equal(b.keys(), [1, 2])?

test "sorted set keeps unique ordered members":
    var set = SortedSet[Int]()
    for value in [4, 2, 4, 9, 1]:
        set.add(value)
    expect_equal(set.values(), [1, 2, 4, 9])?
    expect_equal(set.length(), 4)?
    expect_true(set.contains(9))?
    expect_equal(set.first(), 1)?
    expect_equal(set.last(), 9)?
    expect_equal(set.floor(3), 2)?
    expect_equal(set.ceiling(5), 9)?
    expect_equal(set.range(2, 9), [2, 4])?
    expect_equal(set.pop_first(), 1)?
    expect_equal(set.pop_last(), 9)?
    set.remove(4)
    set.remove(77)
    expect_equal(set.values(), [2])?
    set.clear()
    expect_true(set.is_empty())?
