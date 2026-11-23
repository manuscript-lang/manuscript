// conform: tags=functions,tier-core
// conform: phase=check
// A function declares at most 32 parameters; the 33rd is reported where it is written, not by the lowerer.
fn f(
	a0: Int,
	a1: Int,
	a2: Int,
	a3: Int,
	a4: Int,
	a5: Int,
	a6: Int,
	a7: Int,
	a8: Int,
	a9: Int,
	a10: Int,
	a11: Int,
	a12: Int,
	a13: Int,
	a14: Int,
	a15: Int,
	a16: Int,
	a17: Int,
	a18: Int,
	a19: Int,
	a20: Int,
	a21: Int,
	a22: Int,
	a23: Int,
	a24: Int,
	a25: Int,
	a26: Int,
	a27: Int,
	a28: Int,
	a29: Int,
	a30: Int,
	a31: Int,
	a32: Int,
) Int:
	return a0 + a32

fn main() Void:
	print(f(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32))
