// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/member_cascade_test.go:18 TestUnknownMemberReportsOnce
fn g(v Int) Int {
	return v
}

fn f() Int {
	x := 1
	return g(v: x.foo())
}
// expect-error: MS2001 10:19 unknown or ambiguous member foo on Int; available: abs, clamp, compare, max, milliseconds, min, minutes, seconds, sign, to_binary, to_decimal, to_float, to_float32, to_hex, to_int, to_int16, to_int32, to_int64, to_int8, to_string_radix, to_uint16, to_uint32, to_uint64, to_uint8
