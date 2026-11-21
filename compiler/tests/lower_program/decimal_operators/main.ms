import Decimal, parse_decimal from "@std/math/decimal.ms"

fn sum(a: Decimal, b: Decimal) Decimal:
	return a + b - a * b / b

fn main() Void:
	a := parse_decimal("1.5").get()
	print(sum(a, a).to_string())
