import expect_equal from "@std/test/test.ms"

# A comparator that captures a variable is called from the generated sort thunk instead of
# being inlined into it (its `closure.cap` reads need the closure's own layout). Capturing
# lambdas, nested functions and capture-free comparators must all sort the same way.
type Task:
    name: String
    priority: Int

fn by_length(a: String, b: String) Int:
    return a.length() - b.length()

test "a lambda that captures a map orders by the looked-up counts":
    var freq = Map[String, Int]()
    freq.add("the", 3)
    freq.add("fox", 1)
    freq.add("dog", 2)

    let words = ["fox", "the", "dog"].sorted(
        compare: fn(a: String, b: String) Int: return (freq[b] - freq[a])
    )
    try expect_equal(words, ["the", "dog", "fox"])

test "a nested function that captures a scalar sorts strings":
    let direction = -1
    fn by_len(a: String, b: String) Int:
        return (a.length() - b.length()) * direction
    let words = ["a", "ccc", "bb"].sorted(compare: by_len)
    try expect_equal(words, ["ccc", "bb", "a"])

test "a captured weight orders records and integers":
    let weight = 10
    let tasks = [Task(name: "b", priority: 2), Task(name: "a", priority: 1)].sorted(
        compare: fn(x: Task, y: Task) Int: return (
            x.priority * weight
            - y.priority * weight
        )
    )
    try expect_equal(tasks.get(0).name, "a")

    let offset = 100
    let ints = [3, 1, 2].sorted(
        compare: fn(x: Int, y: Int) Int: return ((y + offset) - (x + offset))
    )
    try expect_equal(ints, [3, 2, 1])

test "a capture-free comparator still sorts":
    try expect_equal(["ccc", "a", "bb"].sorted(compare: by_length), ["a", "bb", "ccc"])

    let plain = ["b", "a"].sorted(
        compare: fn(a: String, b: String) Int: return a.compare(b)
    )
    try expect_equal(plain, ["a", "b"])
