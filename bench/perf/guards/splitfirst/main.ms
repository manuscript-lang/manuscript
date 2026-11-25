// `text.split(sep)[0].clone()` reads only the first piece: no list is built.
fn main() Void {
	line := "name18655 8457"
	var n = 0

	for i in 0..200000 {
		name := line.split(" ").collect()[0].clone()
		n += name.length()
	}

	print(f"{n}")
}
