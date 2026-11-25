// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=sized numeric types stage 2
fn main() Void {
	a Int8 := 1
	b Int32 := a
	c Int8 := b.to_int8()
	d Int16 := a.to_int16().to_int8()
	e Float32 := a.to_float()
	f := a.to_float32().to_int8()
}
// expect-error: MS3001 6:16 expected Int32, found Int8 (in the initializer of 'b')
// expect-error: MS3001 7:17 expected Int8, found Int8? (in the initializer of 'c'); Int8? may be absent; test it first with 'if x != null', or give a default with 'x or default'
// expect-error: MS3001 8:29 expected Int16, found Int8? (in the initializer of 'd'); Int8? may be absent; test it first with 'if x != null', or give a default with 'x or default'
// expect-error: MS3001 9:20 expected Float32, found Float (in the initializer of 'e')
// expect-error: MS2001 10:25 unknown or ambiguous member to_int8 on Float32; available: abs, clamp, compare, is_finite, is_nan, max, min, sign, to_float, to_float64, truncate_to_int
