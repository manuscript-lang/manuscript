import (
	acos,
	acosh,
	asin,
	asinh,
	atan,
	atanh,
	cos,
	cosh,
	sin,
	sinh
) from "@std/math/math.ms"

fn main() Void:
	xs := [1]
	if xs.length() == 0:
		print("empty")
