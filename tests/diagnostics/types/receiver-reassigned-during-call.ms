// conform: tags=testing,tier-core
// conform: phase=check
// A method's receiver is read in place while the arguments run, so an argument cannot
// reassign the variable that holds it.
interface Subtract {
	fn subtract(amount Int) Int
}

type Offset {
	value Int
}

fn Offset.subtract(amount Int) Int => amount - self.value

fn present[T](hold value T) &T? {
	return value
}

export fn main() Int {
	var receiver = Offset(3)
	return receiver.subtract(
		match present(0) {
			_value => {
				receiver = Offset(9)
				10
			} null => 10
		}
	)
}
// expect-error: MS3000 21:21 argument `this value` of `subtract` is moved or changed in place but overlaps the receiver `receiver`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
