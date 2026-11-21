import min_int from "@std/math/math.ms"

limit: Int := 100 - 1

fn clamp(value: Int) Int:
	if value > limit: return limit
	if value == min_int: return 0

	return value

fn main() Void:
	print(clamp(500))
