import (
	floor,
	ceil,
) from "@std/math/math.ms"

fn go(x: Float) Float:
	return floor(x)

export fn main() Void:
	total := Map[String, Int]()
	var row = 0
	while row < 2:
		var column = 0
		while column < 2:
			total["a"] = total.get("a").get(0) + row + column
			column += 1

		row += 1

	print(f"{go(1.5)} {total.get("a").get(0)}")
	return
