greeting: String := "hello"
joined: String := "a" + "b"
primes: List[Int] := [2, 3, 5]
ratios: List[Float] := [0.5, -1.5]
names: List[String] := ["x", "y"]

fn first() Int:
	return primes[0]

fn total() Int:
	var sum = 0
	for p in primes:
		sum += p
	return sum

fn half() Float:
	return ratios[0]

fn shout() String:
	return greeting + "!"

fn copy() String:
	return greeting

fn bound() String:
	text := greeting + joined
	return text

fn second() String:
	return names[1]

fn main() Void:
	print(greeting)
	print(joined)
	print(first() + total())
	print(second())
	print(half())
	print(shout())
	print(copy())
	print(bound())
