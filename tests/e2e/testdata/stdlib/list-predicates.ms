from "@std/testing.ms" import expect_equal, expect_true, expect_false

type Person:
    name: String
    age: Int

def people() -> List[Person]:
    return [Person("ann", 30), Person("bob", 17), Person("cy", 30), Person("di", 17)]

test "any and all stop early and handle empty lists":
    let empty: List[Int] = []
    try expect_false(empty.any(lambda (x: Int) -> Bool: True))
    try expect_true(empty.all(lambda (x: Int) -> Bool: False))

    var calls = 0

    let hit = [1, 2, 3, 4].any(
        lambda (x: Int) -> Bool:
            calls += 1
            return x == 2
    )

    try expect_true(hit)
    try expect_equal(calls, 2)
    calls = 0

    let miss = [1, 2, 3, 4].all(
        lambda (x: Int) -> Bool:
            calls += 1
            return x < 3
    )

    try expect_false(miss)
    try expect_equal(calls, 3)

test "set and map any and all":
    let set = Set([1, 2, 3])
    try expect_true(set.any(lambda (x: Int) -> Bool: x == 3))
    try expect_false(set.all(lambda (x: Int) -> Bool: x < 3))

    let map = {"a": 1, "b": 2}
    try expect_true(map.any(lambda (k: String, v: Int) -> Bool: v == 2))
    try expect_true(map.all(lambda (k: String, v: Int) -> Bool: v > 0))

test "max_by and min_by pick the first of ties and call key once per element":
    let empty: List[Person] = []
    try expect_true(empty.max_by(lambda (p: Person) -> Int: p.age).is_none())
    try expect_true(empty.min_by(lambda (p: Person) -> Int: p.age).is_none())

    var calls = 0

    let oldest = people().max_by(
        lambda (p: Person) -> Int:
            calls += 1
            return p.age
    )

    try expect_equal(calls, 4)
    try expect_equal(
        oldest.map(lambda (p: Person) -> String: p.name.clone()), some("ann")
    )

    let youngest = people().min_by(lambda (p: Person) -> Int: p.age)
    try expect_equal(
        youngest.map(lambda (p: Person) -> String: p.name.clone()), some("bob")
    )

test "max_by supports owned String keys":
    let words = ["pear", "fig", "banana", "kiwi"]
    try expect_equal(
        words.max_by(lambda (w: String) -> String: w.clone()), some("pear")
    )
    try expect_equal(
        words.min_by(lambda (w: String) -> String: w.clone()), some("banana")
    )
