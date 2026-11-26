// conform: tags=numbers,types,faults,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 1
fn main() Void {
	low Int8 := -128
	_flipped := -low
}
// expect-exit: 134
// expect-stderr: Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type
// expect-stderr:   at sized-int-min-negate.ms:6 in main
