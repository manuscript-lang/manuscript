// conform: tags=diagnostics,tier-core
// conform: phase=check
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
// expect-error: MS3070 8:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 9:23 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 10:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 13:12 a constant takes literals, operators, collections, and other constants; compute this value in a function
