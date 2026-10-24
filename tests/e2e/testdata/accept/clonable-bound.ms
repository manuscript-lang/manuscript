import {expect_equal} from "@std/testing.ms"

type Pair:
    left: String
    right: List[Int]

fn twice[T: Clonable](value: T) List[T]:
    return [value.clone(), value]

test "a Clonable bound allows clone on a type parameter":
    expect_equal(twice(3), [3, 3])
    expect_equal(twice("a"), ["a", "a"])
    expect_equal(twice([1, 2]).length(), 2)
    expect_equal(twice(Pair(left: "x", right: [1])) [0].right, [1])
