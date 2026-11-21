import add_with_carry, frexp, modf, multiply_wide, subtract_with_borrow from "@std/math/math.ms"

fn main() Int:
	if add_with_carry(1, 2).carry: return 1
	if subtract_with_borrow(5, 2).borrow: return 2
	if multiply_wide(3, 4).high != 0: return 3
	if frexp(8.0).exponent != 4: return 4
	if modf(2.5).integer != 2.0: return 5
	return 0
