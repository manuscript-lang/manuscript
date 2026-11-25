// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/member_cascade_test.go:17 TestUnknownMemberReportsOnce
fn f() Int {
	x := 1
	y Int := x.foo
	return y
}
// expect-error: MS2001 6:16 unknown or ambiguous member foo on Int; available: abs, clamp, compare, max, milliseconds, min, minutes, seconds, sign, to_binary, to_decimal, to_float, to_float32, to_hex, to_int, to_int16, to_int32, to_int64, to_int8, to_string_radix, to_uint16, to_uint32, to_uint64, to_uint8
