// Guard: a regex with a literal prefix scans with the SIMD prefilter (#4189).
import compile from "@std/regex.ms"

fn main() Void!:
	var text = ""
	for i in 0..4000:
		text += f"line {i} some filler text here\nfunc name{i}(a, b)\n"

	re := compile("func\\s+\\w+\\(")?
	word := compile("[A-Za-z_]+[0-9]+")?
	print(
		f"{(re.find_all(text, null)?).length()} {(word.find_all(text, null)?).length()} {(re.replace_all(text, "fn(", null)?).length()}"
	)
