import expect_equal, expect_true, expect_false from "@std/test.ms"

type Person:
    name: String
    age: Int

fn people() List[Person]:
    return [Person("ann", 30), Person("bob", 17), Person("cy", 30), Person("di", 17)]

test "any and all stop early and handle empty lists":
    let empty: List[Int] = []
    try expect_false(empty.any(fn(x: Int) Bool: true))
    try expect_true(empty.all(fn(x: Int) Bool: false))

    var calls = 0

    let hit = [1, 2, 3, 4].any(
        fn(x: Int) Bool:
            calls += 1
            return x == 2
    )

    try expect_true(hit)
    try expect_equal(calls, 2)
    calls = 0

    let miss = [1, 2, 3, 4].all(
        fn(x: Int) Bool:
            calls += 1
            return x < 3
    )

    try expect_false(miss)
    try expect_equal(calls, 3)

test "set and map any and all":
    let set = Set([1, 2, 3])
    try expect_true(set.any(fn(x: Int) Bool: x == 3))
    try expect_false(set.all(fn(x: Int) Bool: x < 3))

    let map = {"a": 1, "b": 2}
    try expect_true(map.any(fn(k: String, v: Int) Bool: v == 2))
    try expect_true(map.all(fn(k: String, v: Int) Bool: v > 0))

test "max_by and min_by pick the first of ties and call key once per element":
    let empty: List[Person] = []
    try expect_true(empty.max_by(fn(p: Person) Int: p.age).is_none())
    try expect_true(empty.min_by(fn(p: Person) Int: p.age).is_none())

    var calls = 0

    let oldest = people().max_by(
        fn(p: Person) Int:
            calls += 1
            return p.age
    )

    try expect_equal(calls, 4)
    try expect_equal(oldest.map(fn(p: Person) String: p.name.clone()), some("ann"))

    let youngest = people().min_by(fn(p: Person) Int: p.age)
    try expect_equal(youngest.map(fn(p: Person) String: p.name.clone()), some("bob"))

test "max_by supports owned String keys":
    let words = ["pear", "fig", "banana", "kiwi"]
    try expect_equal(words.max_by(fn(w: String) String: w.clone()), some("pear"))
    try expect_equal(words.min_by(fn(w: String) String: w.clone()), some("banana"))

test "max_by and min_by with extreme Int and Float keys":
    let ints = [3, -9223372036854775807 - 1, 3]
    try expect_equal(ints.max_by(fn(x: Int) Int: x), some(3))
    try expect_equal(ints.min_by(fn(x: Int) Int: x), some(-9223372036854775807 - 1))

    let floats = [1.5, -2.5, 1.5]
    try expect_equal(floats.max_by(fn(x: Float) Float: x), some(1.5))
    try expect_equal(floats.min_by(fn(x: Float) Float: x), some(-2.5))

    let ties = ["b", "a", "c"]
    try expect_equal(ties.max_by(fn(w: String) Int: 0), some("b"))
    try expect_equal(ties.min_by(fn(w: String) Int: 0), some("b"))
