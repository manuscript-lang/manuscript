// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/format/format_pipe_test.go:23 TestFormatPipeDotStep
fn run(n Int) Int {
	a := n | .size() | .m()? | .k
	return a
}
// expect-error: MS2001 5:15 unknown or ambiguous member size on Int; available: abs, clamp, compare, max, milliseconds, min, minutes, seconds, sign, to_binary, to_decimal, to_float, to_float32, to_hex, to_int, to_int16, to_int32, to_int64, to_int8, to_string_radix, to_uint16, to_uint32, to_uint64, to_uint8
