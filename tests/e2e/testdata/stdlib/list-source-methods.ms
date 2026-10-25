from "@std/testing.ms" import expect_equal, expect_true

type Plain:
    n: Int

def smallest[T: Comparable & Clonable](values: List[T]) -> Optional[T]:
    return values.min()

test "List operations written in Manuscript apply without an import":
    try expect_equal([4, 5].sum(), 9)
    try expect_equal([4, 5].min(), some(4))
    try expect_equal([4, 5].max(), some(5))
    try expect_equal([5, 4].sorted(), [4, 5])

test "a comparator-less call and a comparator call share a name":
    let items = [Plain(3), Plain(1), Plain(2)]
    let ordered = items.sorted(lambda a, b: a.n - b.n)
    try expect_equal(ordered.map(lambda p: p.n), [1, 2, 3])

    var numbers = [2, 3, 1]
    numbers.sort()
    try expect_equal(numbers, [1, 2, 3])
    numbers.sort(lambda a, b: b - a)
    try expect_equal(numbers, [3, 2, 1])

test "the bound is carried through a generic function":
    try expect_equal(smallest(["b", "a"]), some("a"))
    try expect_true(smallest(List[Int]()).is_none())
