import Decimal from "@std/math/decimal.ms"

fn compare_decimals(a: Decimal, b: Decimal) Int:
	return a.compare(b)

fn decimal_text(a: Decimal) String:
	return a.to_string()

fn decimal_float(a: Decimal) Float?:
	return a.to_float()

fn decimal_integer(a: Decimal) Int?:
	return a.truncate_to_int()

fn main() Void:
	print(1)
