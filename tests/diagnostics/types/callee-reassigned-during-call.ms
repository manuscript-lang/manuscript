// conform: tags=testing,tier-core
// conform: phase=check
// A function value a variable holds is called in place, so an argument cannot reassign
// that variable while the call runs: the value being called would be dropped under the
// call.
fn subtract(amount Int, deduction Int) Int => amount - deduction

fn present[T](hold value T) &T? {
	return value
}

export fn main() Int {
	var selected = subtract
	return selected(
		match present(0) {
			_value => {
				selected = fn(amount Int, deduction Int) Int => amount + deduction
				10
			} null => 10
		},
		3
	)
}
// expect-error: MS3000 14:12 argument `this value` of `selected` is moved or changed in place but overlaps the called value `selected`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
