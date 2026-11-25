// conform: tags=strings,tier-core
// conform: phase=run

// `for piece in text.split(sep)` visits the pieces by byte offset with no list; the pieces are the ones
// `split` returns, for every shape of text and separator.
fn show(label String, parts List[String]) Void {
	print(f"{label}: {parts.length()} {parts}")
}

fn pieces(text, sep String) List[String] {
	var out = List[String]()
	for piece in text.split(sep) {
		out.append(piece)
	}
	return out
}

fn separator() String {
	print("separator evaluated")
	return ","
}

fn main() Void {
	show("plain", pieces("a,b,c", ","))
	show("empty text", pieces("", ","))
	show("no separator in text", pieces("abc", ","))
	show("leading", pieces(",a", ","))
	show("trailing", pieces("a,", ","))
	show("only separator", pieces(",", ","))
	show("adjacent", pieces("a,,b", ","))
	show("long separator", pieces("a--b----c-", "--"))
	show("partial separator", pieces("a-b--c", "--"))
	show("empty separator", pieces("héllo", ""))
	show("empty separator, empty text", pieces("", ""))
	show("multibyte separator", pieces("x→y→→z", "→"))
	show(
		"long pieces",
		pieces("a long piece of text,another long piece of text,short", ","),
	)

	var seen = 0

	for piece in "one,two,three,four".split(separator()) {
		seen += 1
		if piece == "three" { break }
	}

	print(f"seen {seen}")

	var skipped = 0

	for piece in "a,,b,,c".split(",") {
		if piece.is_empty() { continue }

		skipped += piece.length()
	}

	print(f"kept {skipped}")

	var keep = List[String]()
	text := "first line here\nsecond line is longer than fifteen\nthird"

	for line in text.split("\n") {
		for word in line.split(" ") {
			keep.append(word)
		}
		keep.append(line)
	}

	print(f"{keep.length()} {keep[1]} {keep[keep.length() - 1]}")
}
