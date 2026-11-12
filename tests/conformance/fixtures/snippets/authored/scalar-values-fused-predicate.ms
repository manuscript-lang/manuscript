// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=scalar-values-fused
// all, any and count over scalar_values() with a reading lambda run as one decoding loop; the
// answers must match the list-building form, including non-ASCII text and empty text.

fn digits(s: String) Bool:
	return not s.is_empty() and s.scalar_values().all(fn c: c >= 48 and c <= 57)

export fn main() Int:
	print(digits("12345"))
	print(digits("12a45"))
	print(digits(""))
	print(digits("12é45"))
	print("héllo wörld 🙂".scalar_values().count(fn c: c > 127))
	print("héllo wörld 🙂".scalar_values().any(fn c: c == 128578))
	print("plain ascii".scalar_values().any(fn c: c > 127))
	print("".scalar_values().all(fn c: c > 127))
	print("".scalar_values().any(fn c: c > 127))
	limit := 100
	var total = 0
	for i in 0..50:
		text := "row {i} é"
		total += text.scalar_values().count(fn c: c < limit)
	print(total)
	print("{"abc".scalar_values().all(fn c: c >= 97)} {"abc".clone().scalar_values().count(fn c: c == 98)}")
	return 0
