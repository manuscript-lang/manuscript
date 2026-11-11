// conform: tags=testing,tier-core
// conform: phase=check
// A function value a variable holds is called in place, so an argument cannot reassign
// that variable while the call runs: the value being called would be dropped under the
// call.
fn subtract(amount: Int, deduction: Int) Int: amount - deduction

fn present[T](value: T) T?:
	return value

export fn main() Int:
	var selected = subtract
	return selected(
		match present(0):
			_value:
				selected = fn(amount: Int, deduction: Int) Int: amount + deduction
				10
			none: 10
		,
		3
	)
