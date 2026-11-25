// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=sized numeric types stage 1
fn main() Void {
	a Int32 := 1
	b Int64 := 2
	mixed := a + b
	plain Int := 3
	both Int8 := plain
	rem Float32 := 1.5
	bad := rem % rem
}
// expect-error: MS3001 7:16 operator operands require the same independently known type, found Int32 + Int; convert one side so both have one type (e.g. interpolate into text with f"{value}", or convert between Int and Float)
// expect-error: MS3001 9:18 expected Int8, found Int (in the initializer of 'both')
// expect-error: MS3000 11:16 remainder requires integer operands, found Float32; convert to Int or use math functions
