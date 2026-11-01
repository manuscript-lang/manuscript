import expect_equal, expect_true from "@std/test/test.ms"
import SearchResult from "@std/collections/collections.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"

fn linear_search[T: Comparable](values: List[T], target: T) SearchResult:
    for i in 0..values.length():
        let order = values[i].compare(target)
        if order >= 0:
            return SearchResult(i, order == 0)

    return SearchResult(values.length(), false)

fn check_search[T: Comparable](values: List[T], target: T) Unit!:
    let expected = linear_search(values, target)
    let actual = values.binary_search(target)
    try expect_equal(actual.index, expected.index)
    try expect_equal(actual.found, expected.found)
    return ok(unit)

# Equality is by key, so equal keys can have different payloads.
type Key:
    value: Int
    label: String

impl Comparable for Key:
    fn compare(other: Key) Int:
        return self.value.compare(other.value)

type Counted:
    value: Int
    comparisons: Shared[Int]

impl Comparable for Counted:
    fn compare(other: Counted) Int:
        var guard = lock(self.comparisons)
        guard.value += 1
        return self.value.compare(other.value)

test "binary search reports the first duplicate or insertion position":
    let values = [1, 3, 3, 3, 5]
    for target in - 1..8:
        try check_search(values, target)
    try expect_equal(values.binary_search(3).index, 1)
    try expect_equal(values.binary_search(4).index, 4)
    try expect_equal(values, [1, 3, 3, 3, 5])
    try check_search(List[Int](), 0)

    for target in 0..3:
        try check_search([1], target)
        try check_search([1, 1, 1, 1], target)

    var inserted = values.clone()
    let missing = inserted.binary_search(4)
    inserted.insert(missing.index, 4)
    try expect_equal(inserted, [1, 3, 3, 3, 4, 5])

test "binary search handles full-width extrema and sized numbers":
    let minimum = -9223372036854775808
    let maximum = 9223372036854775807
    let values = [minimum, minimum, -1, 0, maximum]
    for target in [minimum, minimum + 1, -1, 0, 1, maximum - 1, maximum]:
        try check_search(values, target)

    let narrow: List[Int8] = [-128, -1, 0, 127]
    let target: Int8 = -1
    try check_search(narrow, target)

    let unsigned: List[UInt64] = [0, 9223372036854775808, 18446744073709551615]
    let large: UInt64 = 18446744073709551615
    try check_search(unsigned, large)
    try check_search(["", "apple", "apple", "pear"], "apple")
    try check_search(["", "apple", "pear"], "fig")
    try check_search(["", "apple", "pear"], "z")

test "binary search uses Comparable equality and works through a generic bound":
    let values = [Key(3, "last"), Key(1, "first"), Key(1, "second")].sorted()
    let result = values.binary_search(Key(1, "different payload"))
    try expect_true(result.found)
    try expect_equal(result.index, 0)
    try expect_equal(values[result.index].label, "first")
    try check_search(values, Key(2, "missing"))

# Lists are sorted before searching: search does not scan to validate this precondition.
test "binary search agrees with a linear oracle over sorted duplicate-heavy lists":
    for length in 0..65:
        for seed in 0..13:
            let values = (0..length).map(fn i: (i * 17 + seed * 7) % 23 - 11).sorted()
            for target in - 12..13:
                try check_search(values, target)

test "binary search matches sorted Float ordering including NaN and signed zero":
    let nan = 0.0 / 0.0
    let infinity = 1.0 / 0.0
    let values = [nan, 2.0, -0.0, -infinity, nan, 0.0, infinity, -1.0].sorted()
    for target in [-infinity, -2.0, -1.0, -0.0, 0.0, 1.0, infinity, nan]:
        try check_search(values, target)
    try expect_equal(values.binary_search(nan).index, 6)
    try expect_true(values.binary_search(nan).found)
    try expect_equal(values.binary_search(0.0).index, 2)
    try expect_equal([nan, nan].binary_search(nan).index, 0)
    try expect_equal([0.0, infinity].binary_search(nan).index, 2)
    try expect_true(not [0.0, infinity].binary_search(nan).found)

    let narrow: List[Float32] = [0.0, 1.0, nan.to_float32().get()]
    let narrow_nan: Float32 = nan.to_float32().get()
    try check_search(narrow, narrow_nan)

test "binary search uses logarithmically many comparisons":
    for length in [0, 1, 2, 3, 4, 7, 8, 31, 32, 255, 1024, 65536]:
        let comparisons = share(0)
        let values = (0..length).map(fn i: Counted(i / 3 * 2, comparisons))
        var budget = 1
        var remaining = length

        while remaining > 0:
            budget += 1
            remaining /= 2

        for target in [-1, 0, length / 3, length / 2, length]:
            var before = lock(comparisons)
            before.value = 0
            try before.close()

            let result = values.binary_search(Counted(target, comparisons))
            var after = lock(comparisons)
            try expect_true(after.value <= budget)
            if length == 0:
                try expect_equal(after.value, 0)
            try expect_true(result.index >= 0 and result.index <= length)
