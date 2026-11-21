fn parse(text: String) Int!:
	if text == "": return error(Error("empty"))
	return ok(1)

fn first(text: String) Int:
	if n := parse(text): return n
	return 0

fn main() Void:
	print(first("a"))
