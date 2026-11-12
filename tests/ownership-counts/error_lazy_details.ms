// expect-stdout: 0
// expect-stdout: 2
// expect-stdout: 3
// expect-stdout: 1
// expect-stdout: true
// expect-stdout: false
// expect-stdout: 4
// expect-stdout: 3
// An Error keeps its details map behind a pointer that stays null until a detail
// exists. Building, reading, changing, copying, comparing and dropping one, with and
// without details, leaves no block.

fn plain() Error:
	return Error("plain", kind: "EINVAL")

fn detailed() Error:
	return Error("detailed", kind: "ENOENT", details: {"path": "/a", "op": "open"})

fn fails(i: Int) Int!:
	if i % 2 == 0: return error(plain())
	return error(detailed())

fn main() Unit:
	empty := plain()
	print(empty.details.length())

	full := detailed()
	print(full.details.length())

	var grown = plain()
	grown.details.add("a", "1")
	grown.details.add("b", "2")
	grown.details.add("c", "3")
	print(grown.details.length())

	var again = plain()
	again.details.add("k", "v")
	again.details.remove("k")
	print(again.details.length() + 1)
	print(plain() == plain())
	print(plain() == detailed())

	var seen = 0

	for i in 0..4:
		r := fails(i)
		seen += r.err().details.length()

	print(seen)

	copy := grown.clone()
	print(copy.details.length())
