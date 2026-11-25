// conform: tags=numbers,types,tier-core
// conform: phase=check
// conform: origin=unsigned integer types stage 2
export fn main() Int {
	too_big UInt64 := 18446744073709551616
	negative UInt64 := -1
	mixed UInt64 := 5
	n Int := 3
	sum := mixed + n
	flipped := -mixed
	return 0
}
// expect-error: MS3070 5:23 literal 18446744073709551616 is out of range for UInt64; use a value between 0 and 18446744073709551615
// expect-error: MS3070 6:25 literal -1 is out of range for UInt64; use a value between 0 and 18446744073709551615
// expect-error: MS3001 9:18 operator operands require the same independently known type, found UInt64 + Int; convert one side so both have one type (e.g. interpolate into text with f"{value}", or convert between Int and Float)
// expect-error: MS3000 10:16 unary - is not defined for UInt64; subtract from zero with a wider signed type, e.g. 0 - x.to_int()
