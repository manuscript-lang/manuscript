enum Tok:
	num(value: Int)
	plus
	star
	open
	close

fn tokens(text: String) List[Tok]:
	var out: List[Tok] = []
	var i = 0
	n := text.length()

	while i < n:
		c := text.scalar_at(i)

		if c == 32:
			i += 1
		else if c == 43:
			out.append(Tok.plus)
			i += 1
		else if c == 42:
			out.append(Tok.star)
			i += 1
		else if c == 40:
			out.append(Tok.open)
			i += 1
		else if c == 41:
			out.append(Tok.close)
			i += 1
		else:
			var v = 0

			while i < n and text.scalar_at(i) >= 48 and text.scalar_at(i) <= 57:
				v = v * 10 + text.scalar_at(i) - 48
				i += 1

			out.append(Tok.num(v))

	return out

fn main() Unit:
	text := "(12 + 345) * 6 + (7 * (89 + 10)) ".repeat(20000).get()
	toks := tokens(text)
	var nums = 0
	var ops = 0

	for t in toks:
		match t:
			Tok.num(v): nums += v
			_: ops += 1

	print("{toks.length()} {nums} {ops}")
