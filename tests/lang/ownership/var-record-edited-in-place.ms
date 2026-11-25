// conform: tags=ownership,var-parameters
// conform: phase=run
type Cursor {
	items List[String]
	pos Int
	seen Int
}

fn advance(var hold cursor Cursor) &String {
	cursor.pos += 1
	return cursor.items[cursor.pos - 1]
}

fn skip_blank(var cursor Cursor) Void {
	while cursor.pos < cursor.items.length() and cursor.items[cursor.pos] == "" {
		cursor.pos += 1
	}
}

fn scan(var cursor Cursor) String! {
	var out = ""

	while cursor.pos < cursor.items.length() {
		skip_blank(cursor)
		if cursor.pos >= cursor.items.length() {
			break
		}

		word := advance(cursor).clone()
		if word == "stop" {
			return error(Error("stopped"))
		}

		cursor.seen += 1
		out += word
	}

	return ok(out)
}

fn main() Void {
	var cursor = Cursor(["a", "", "b", "", "", "c"], 0, 0)
	print(scan(cursor).get())
	print(f"{cursor.pos} {cursor.seen}")

	var again = Cursor(["x", "stop", "y"], 0, 0)
	result := scan(again)
	print(result.is_error())
	print(f"{again.pos} {again.seen}")
}
// expect-exit: 0
// expect-stdout: abc
// expect-stdout: 6 3
// expect-stdout: true
// expect-stdout: 2 1
