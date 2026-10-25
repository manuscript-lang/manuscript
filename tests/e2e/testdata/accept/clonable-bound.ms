from "@std/testing.ms" import expect_equal

type Pair:
    left: String
    right: List[Int]

def twice[T: Clonable](value: T) -> List[T]:
    return [value.clone(), value]

test "a Clonable bound allows clone on a type parameter":
    try expect_equal(twice(3), [3, 3])
    try expect_equal(twice("a"), ["a", "a"])
    try expect_equal(twice([1, 2]).length(), 2)
    try expect_equal(twice(Pair(left: "x", right: [1])) [0].right, [1])
