// A destructuring `for` pattern follows `let` rules: the element must match the
// pattern's shape, and the pattern's names are scoped to the body.
export fn main() Int:
	numbers := [1, 2, 3]

	for [a, b] in numbers:  // error: positional binding requires a list
		print(a)  // error: unknown binding a

	for {x} in [[1, 2]]:  // error: record binding requires a record
		print(x)  // error: unknown binding x

	for [a, b] in [[1, 2]]:
		print(a + b)

	print(b)  // error: unknown binding b
	return 0
