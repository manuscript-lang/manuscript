import panic from "@std/core.ms"

fn add(a, b Int) Int => a + b

fn main() Int {
	var sum = 0
	for i in 0..5000000 {
		sum = add(sum, i)
	}
	if sum != 12499997500000 { return panic("calls checksum") }

	return 0
}
