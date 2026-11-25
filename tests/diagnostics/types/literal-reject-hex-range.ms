// conform: tags=numbers,diagnostics,tier-core
// conform: phase=check
// conform: origin=hex literal range
export fn main() Int {
	x := 0xFFFF_FFFF_FFFF_FFFF
	return x
}
// expect-error: MS3070 5:10 Int literal is outside signed 64-bit range; use a value between -9223372036854775808 and 9223372036854775807, or BigInt
