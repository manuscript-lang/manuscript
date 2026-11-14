// String manipulation: interpolation, case, trim, replace, split and join, search,
// padding, and sorting strings.
import StringBuilder from "@std/string_builder.ms"

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn main() Unit:
	var x = 21
	var words: List[String] = []

	for i in 0..300000:
		x = lcg(x)
		words.append("  Item-{x % 100000}_{x / 3 % 977} ")

	var upper_len = 0
	var replaced = 0
	var found = 0
	var padded = 0

	for w in words:
		t := w.trim()
		upper_len += t.upper().length()
		replaced += t.replace("_", "--").replace("Item", "I").length()
		if t.contains("77"): found += 1
		if i := t.index_of("-"): found += i
		padded += t.pad_start(20, ".").length() + t.lower().pad_end(24, "*").length()

	joined := words.map(fn w: w.trim().clone()).sorted(fn a, b: a.compare(b))
	var sorted_sample = 0
	for i in 0..joined.length():
		if i % 1000 == 0: sorted_sample += joined[i].length() + joined[i].scalar_at(5)

	var sb = StringBuilder()
	var size = 0

	for w in joined:
		if size > 200000: break

		sb.append(w)
		sb.append(",")
		size += w.length() + 1

	parts := sb.build().split(",")
	print(
		"upper {upper_len} replaced {replaced} found {found} padded {padded} sorted {sorted_sample} parts {parts.length()}"
	)
