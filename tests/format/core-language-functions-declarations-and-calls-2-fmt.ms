// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:31
fn reduce(amount Int, deduction Int) Int {
	return amount - deduction
}

remaining := reduce(10, 3)
explicit_remaining := reduce(amount: 10, deduction: 3)
mixed := reduce(deduction: 3, 10)
amount := 10
deduction := 3
swapped := reduce(deduction: deduction, amount: amount)
// expect-format: rewritten
// expect-formatted: fn reduce(amount, deduction Int) Int {
// expect-formatted: \treturn amount - deduction
// expect-formatted: }
// expect-formatted:
// expect-formatted: remaining := reduce(10, 3)
// expect-formatted: explicit_remaining := reduce(amount: 10, deduction: 3)
// expect-formatted: mixed := reduce(deduction: 3, 10)
// expect-formatted: amount := 10
// expect-formatted: deduction := 3
// expect-formatted: swapped := reduce(deduction: deduction, amount: amount)
