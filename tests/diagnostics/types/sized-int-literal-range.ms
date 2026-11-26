// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=sized numeric types stage 1
fn main() Void {
	too_big Int8 := 128
	too_small Int8 := -129
	wide Int32 := 3000000000
	hot Float32 := 1e39
}
// expect-error: MS3070 5:21 literal 128 is out of range for Int8; use a value between -128 and 127
// expect-error: MS3070 6:24 literal -129 is out of range for Int8; use a value between -128 and 127
// expect-error: MS3070 7:19 literal 3000000000 is out of range for Int32; use a value between -2147483648 and 2147483647
// expect-error: MS3070 8:20 Float literal is outside finite binary32 range; use a smaller magnitude (about 3.4e38 at most)
