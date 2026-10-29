import expect_equal from "@std/test.ms"

type Pair:
    left: String
    right: List[Int]

fn twice[T: Clonable](value: T) List[T]:
    return [value.clone(), value]

test "a Clonable bound allows clone on a type parameter":
    try expect_equal(twice(3), [3, 3])
    try expect_equal(twice("a"), ["a", "a"])
    try expect_equal(twice([1, 2]).length(), 2)
    try expect_equal(twice(Pair(left: "x", right: [1])) [0].right, [1])

fn keep[T: Clonable](value: T) T:
    let copy: T = value.clone()
    return copy

interface Duplicator:
    fn duplicate() Self

type Token:
    id: Int

impl Duplicator for Token:
    fn duplicate() Token:
        return Token(id: self.id)

fn duplicated[T: Duplicator](value: T) T:
    return value.duplicate()

test "Self as a result type is the implementing type":
    try expect_equal(keep("a"), "a")
    try expect_equal(duplicated(Token(id: 4)).id, 4)
