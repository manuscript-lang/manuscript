// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=unsigned integer types stage 1
fn main() Void {
	a UInt8 := 256
	b UInt8 := -1
	c UInt8 := 5
	d := -c
	e Int := c
	f UInt8 := e
	g UInt16 := c
	h := c + 300
	i UInt8 := 3 - 5
}
// expect-error: MS3070 5:16 literal 256 is out of range for UInt8; use a value between 0 and 255
// expect-error: MS3070 6:17 literal -1 is out of range for UInt8; use a value between 0 and 255
// expect-error: MS3000 8:10 unary - is not defined for UInt8; subtract from zero with a wider signed type, e.g. 0 - x.to_int()
// expect-error: MS3001 9:14 expected Int, found UInt8 (in the initializer of 'e')
// expect-error: MS3001 10:16 expected UInt8, found Int (in the initializer of 'f')
// expect-error: MS3001 11:17 expected UInt16, found UInt8 (in the initializer of 'g')
// expect-error: MS3070 12:14 literal 300 is out of range for UInt8; use a value between 0 and 255
// expect-error: MS3000 13:18 3 - 5 overflows UInt8 and always faults; use a smaller value or a wider type such as BigInt
