import BigInt, big_int_of_int from "@std/math/math.ms"

fn product(n: Int) Int:
	var total = big_int_of_int(1)
	total *= big_int_of_int(n)
	total += big_int_of_int(2)
	return total.sign()

fn factorial(n: Int) BigInt:
	var total = big_int_of_int(1)
	var i = 2

	while i <= n:
		total *= big_int_of_int(i)
		i += 1

	return total

fn pick(flag: Bool) Int:
	var total = big_int_of_int(5)
	if flag:
		total += total
	return total.sign()

fn main() Void:
	print(product(3))
	print(factorial(4).sign())
	print(pick(true))
