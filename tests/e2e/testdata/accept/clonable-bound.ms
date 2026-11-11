import expect_equal from "@std/test/test.ms"

type Pair:
	left: String
	right: List[Int]

fn twice[T: Clonable](value: T) List[T]:
	return [value.clone(), value]

test "a Clonable bound allows clone on a type parameter":
	expect_equal(twice(3), [3, 3])?
	expect_equal(twice("a"), ["a", "a"])?
	expect_equal(twice([1, 2]).length(), 2)?
	expect_equal(twice(Pair(left: "x", right: [1]))[0].right, [1])?

fn keep[T: Clonable](value: T) T:
	copy: T := value.clone()
	return copy

interface Duplicator:
	fn duplicate() Self

type Token:
	id: Int

fn Token.duplicate() Token:
	return Token(id: self.id)

fn duplicated[T: Duplicator](value: T) T:
	return value.duplicate()

test "Self as a result type is the implementing type":
	expect_equal(keep("a"), "a")?
	expect_equal(duplicated(Token(id: 4)).id, 4)?
