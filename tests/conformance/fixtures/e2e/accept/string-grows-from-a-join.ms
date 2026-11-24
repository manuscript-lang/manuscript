// conform: tags=strings,interpolation,tier-core
// conform: phase=run
// `s = s + pieces` in a loop grows `s` in place: the text stays right when a piece is an
// integer, a wide character, `s` itself, or more pieces than one join takes.
fn rows(n Int) String {
	var out = "["

	for i in 0..n {
		if i > 0 { out += "," }
		out += f"\{\"id\":{i},\"name\":\"item-{i}\"\}"
	}

	out += "]"
	return out
}

fn wide(n Int) String {
	var out = "start"
	for i in 0..n {
		out += f"{i}:{i + 1}:{i + 2}:{i + 3}:é:{i + 4}|"
	}
	return out
}

fn doubled(seed String) String {
	var out = seed.clone()
	for i in 0..3 {
		out += f"<{out}>{i}"
	}
	return out
}

fn main() Int {
	print(rows(3))

	big := rows(5000)
	print(big.length())
	print(big.ends_with(",{\"id\":4999,\"name\":\"item-4999\"}]"))
	print(wide(2))
	print(wide(400).length())
	print(doubled("abcdefghijklmnopqrstuvwxyz").length())
	print(doubled("ab"))

	var short = ""
	for i in 0..4 {
		short += f"{i}"
	}
	print(short)

	var n = "n"
	for i in 8..11 {
		n += i.to_string()
	}
	print(n)

	var parts = "p"
	for i in 0..2 {
		parts = parts + "-" + i.to_string() + "-" + f"{i * 2}" + "!"
	}
	print(parts)
	return 0
}
