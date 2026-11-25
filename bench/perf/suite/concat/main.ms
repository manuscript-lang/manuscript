// Building one long string by appending: `+=` with a number, an interpolation and a
// literal, and `join`.
fn main() Void {
	var a = ""
	for i in 0..50000 {
		a += i.to_string()
	}

	var b = ""
	for i in 0..50000 {
		b += f"item-{i},"
	}

	var c = ""
	for i in 0..50000 {
		c += "item,"
	}

	var parts List[String] = []
	for i in 0..50000 {
		parts.append(f"p{i}")
	}

	d := parts.join(",")
	print(f"{a.length()} {b.length()} {c.length()} {d.length()}")
}
