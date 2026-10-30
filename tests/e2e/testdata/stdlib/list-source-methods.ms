import expect_equal, expect_true from "@std/test.ms"

type Plain:
    n: Int

fn smallest[T: Comparable & Clonable](values: List[T]) T?:
    return values.min()

test "List operations written in Manuscript apply without an import":
    try expect_equal([4, 5].sum(), 9)
    try expect_equal([4, 5].min(), some(4))
    try expect_equal([4, 5].max(), some(5))
    try expect_equal([5, 4].sorted(), [4, 5])

test "a comparator-less call and a comparator call share a name":
    let items = [Plain(3), Plain(1), Plain(2)]
    let ordered = items.sorted(fn a, b: a.n - b.n)
    try expect_equal(ordered.map(fn p: p.n), [1, 2, 3])

    var numbers = [2, 3, 1]
    numbers.sort()
    try expect_equal(numbers, [1, 2, 3])
    numbers.sort(fn a, b: b - a)
    try expect_equal(numbers, [3, 2, 1])

test "the bound is carried through a generic function":
    try expect_equal(smallest(["b", "a"]), some("a"))
    try expect_true(smallest(List[Int]()).is_none())

test "keys of a temporary list is built and released once":
    try expect_equal([7, 8, 9].keys(), [0, 1, 2])
    try expect_equal(["a", "b"].keys().length() + ["c"].keys().length(), 3)
    try expect_equal(List[Int]().keys(), List[Int]())
