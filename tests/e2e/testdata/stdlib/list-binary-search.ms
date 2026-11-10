import (
    expect_equal, expect_ok, expect_true from "@std/test/test.ms",
    SearchResult from "@std/collections/collections.ms",
    append_file, read_file, temporary, write_file from "@std/os/fs.ms",
)

fn linear_search[T: Comparable](values: List[T], target: T) SearchResult:
    for i in 0..values.length():
        order := values[i].compare(target)
        if order >= 0: return SearchResult(i, order == 0)

    return SearchResult(values.length(), false)

fn check_search[T: Comparable](values: List[T], target: T) Unit!:
    expected := linear_search(values, target)
    actual := values.binary_search(target)
    try expect_equal(actual.index, expected.index)
    try expect_equal(actual.found, expected.found)

// Equality is by key, so equal keys can have different payloads.
type Key:
    value: Int
    label: String

impl Comparable for Key:
    fn compare(other: Key) Int:
        return self.value.compare(other.value)

type Counted:
    value: Int
    comparisons: String

impl Comparable for Counted:
    fn compare(other: Counted) Int:
        _ := append_file(self.comparisons, "x").wait()
        return self.value.compare(other.value)

test "binary search reports the first duplicate or insertion position":
    values := [1, 3, 3, 3, 5]
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
    missing := inserted.binary_search(4)
    inserted.insert(missing.index, 4)
    try expect_equal(inserted, [1, 3, 3, 3, 4, 5])

test "binary search handles full-width extrema and sized numbers":
    minimum := -9223372036854775808
    maximum := 9223372036854775807
    values := [minimum, minimum, -1, 0, maximum]
    for target in [minimum, minimum + 1, -1, 0, 1, maximum - 1, maximum]:
        try check_search(values, target)

    narrow: List[Int8] = [-128, -1, 0, 127]
    target: Int8 = -1
    try check_search(narrow, target)

    unsigned: List[UInt64] = [0, 9223372036854775808, 18446744073709551615]
    large: UInt64 = 18446744073709551615
    try check_search(unsigned, large)
    try check_search(["", "apple", "apple", "pear"], "apple")
    try check_search(["", "apple", "pear"], "fig")
    try check_search(["", "apple", "pear"], "z")

test "binary search uses Comparable equality and works through a generic bound":
    values := [Key(3, "last"), Key(1, "first"), Key(1, "second")].sorted()
    result := values.binary_search(Key(1, "different payload"))
    try expect_true(result.found)
    try expect_equal(result.index, 0)
    try expect_equal(values[result.index].label, "first")
    try check_search(values, Key(2, "missing"))

// Lists are sorted before searching: search does not scan to validate this precondition.
test "binary search agrees with a linear oracle over sorted duplicate-heavy lists":
    for length in 0..65:
        for seed in 0..13:
            values := (0..length).map(fn i: (i * 17 + seed * 7) % 23 - 11).sorted()
            for target in - 12..13:
                try check_search(values, target)

test "binary search matches sorted Float ordering including NaN and signed zero":
    nan := 0.0 / 0.0
    infinity := 1.0 / 0.0
    values := [nan, 2.0, -0.0, -infinity, nan, 0.0, infinity, -1.0].sorted()
    for target in [-infinity, -2.0, -1.0, -0.0, 0.0, 1.0, infinity, nan]:
        try check_search(values, target)
    try expect_equal(values.binary_search(nan).index, 6)
    try expect_true(values.binary_search(nan).found)
    try expect_equal(values.binary_search(0.0).index, 2)
    try expect_equal([nan, nan].binary_search(nan).index, 0)
    try expect_equal([0.0, infinity].binary_search(nan).index, 2)
    try expect_true(not [0.0, infinity].binary_search(nan).found)

    narrow: List[Float32] = [0.0, 1.0, nan.to_float32().get()]
    narrow_nan: Float32 = nan.to_float32().get()
    try check_search(narrow, narrow_nan)

fn count(path: String) Int:
    read := read_file(path).wait()
    if bytes := read: return bytes.length()

    return 0

test "binary search uses logarithmically many comparisons":
    tmp := temporary("ms-bs-") | try expect_ok
    comparisons := "{tmp.path()}/count"

    for length in [0, 1, 2, 3, 4, 7, 8, 31, 32, 255, 1024, 65536]:
        values := (0..length).map(fn i: Counted(i / 3 * 2, comparisons.clone()))
        var budget = 1
        var remaining = length

        while remaining > 0:
            budget += 1
            remaining /= 2

        for target in [-1, 0, length / 3, length / 2, length]:
            try write_file(comparisons.clone(), "", true).wait()

            result := values.binary_search(Counted(target, comparisons.clone()))
            used := count(comparisons.clone())
            try expect_true(used <= budget)
            if length == 0:
                try expect_equal(used, 0)
            try expect_true(result.index >= 0 and result.index <= length)
