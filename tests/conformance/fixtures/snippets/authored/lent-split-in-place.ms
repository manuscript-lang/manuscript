// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=lent-split
// A lent `split` result used in place, and a `.clone()` that keeps it.
type Row:
	fields: List[String]

fn latency(line: String) Int:
	f := line.split(" ")
	return f[1].length() + f.length()

fn keep(line: String) Row:
	return Row(line.split(" ").clone())

fn longest(text: String) String:
	var best = ""
	for p in text.split(","):
		if p.length() > best.length():
			best = p.clone()
	return best

// The pieces are views of `rest`, which dies when the function returns: the clone must own them.
fn components(text: String) List[String]:
	rest := text.cut_prefix("/").get(text)
	return rest.split("/").clone()

export fn main() Int:
	print(components("/alpha/beta/gamma/delta/epsilon/zeta/eta/theta"))
	print(latency("alpha beta gamma"))
	print(keep("a b c").fields.length())
	print(longest("x,yyyy,zz,wwwwwwwwwwwwwwwwwwwwwwwwwwww"))
	var line = "one two"
	parts := line.split(" ").clone()
	line = ""
	print(parts)
	return 0
