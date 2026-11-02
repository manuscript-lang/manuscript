import expect_equal from "@std/test/test.ms"

type Inner:
    count: Int
    tag: String?

type Outer:
    inner: Inner?
    name: String

type Counter:
    calls: Int

impl Counter:
    fn scaled(by: Int) Int:
        return self.calls * by

fn count_of(outer: Outer?) Int?:
    return outer?.inner?.count

fn bump(var counter: Counter) Int:
    counter.calls += 100
    return 2

test "a chain is none at the first absent link":
    let full: Outer? = Outer(inner: Inner(count: 4, tag: "x"), name: "n")
    let hollow: Outer? = Outer(inner: none, name: "n")
    let nothing: Outer? = none
    let four: Int? = 4
    try expect_equal(count_of(full), four)
    try expect_equal(count_of(hollow), none)
    try expect_equal(count_of(nothing), none)

test "an optional field flattens instead of nesting":
    let full: Outer? = Outer(inner: Inner(count: 4, tag: "x"), name: "n")
    let untagged: Outer? = Outer(inner: Inner(count: 4, tag: none), name: "n")
    let tag = full?.inner?.tag.clone()
    let x: String? = "x"
    try expect_equal(tag, x)
    try expect_equal(untagged?.inner?.tag, none)

test "a plain field makes the chain optional":
    let present: Outer? = Outer(inner: none, name: "abc")
    let absent: Outer? = none
    let three: Int? = 3
    try expect_equal(present?.name.length(), three)
    try expect_equal(absent?.name.length(), none)

test "a call's arguments run only when the receiver is present":
    var counter = Counter(calls: 0)
    let absent: Counter? = none
    try expect_equal(absent?.scaled(bump(var counter)), none)
    try expect_equal(counter.calls, 0)

    let present: Counter? = Counter(calls: 3)
    let six: Int? = 6
    try expect_equal(present?.scaled(bump(var counter)), six)
    try expect_equal(counter.calls, 100)
