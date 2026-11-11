// A method's receiver is read in place while the arguments run, so an argument cannot
// reassign the variable that holds it.
interface Subtract:
	fn subtract(amount: Int) Int

type Offset:
	value: Int

fn Offset.subtract(amount: Int) Int: amount - self.value

fn present[T](value: T) T?:
	return value

export fn main() Int:
	var receiver = Offset(3)
	return receiver.subtract(
		match present(0):
			_value:
				receiver = Offset(9)
				10
			none: 10
	)
