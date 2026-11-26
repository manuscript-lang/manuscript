// conform: tags=text,scope-cleanup,tier-core
// conform: phase=run
// A join whose first part is an owned string that dies at the join grows it in place;
// the same join reached on another path builds a new string and drops every part. Both
// must leave no owned part behind.
type Note {
	message String
}

fn text(words String, domain String, move said String) Note {
	if words == "-" {
		if said.length() > 0 {
			return Note(said)
		}
		return Note(f"{domain}: failed")
	}

	if said.starts_with(f"{domain}: ") {
		return Note(said)
	}
	if said.length() > 0 {
		return Note(f"{domain}: {words}: {said}")
	}

	return Note(f"{domain}: {words}")
}

fn main() Void {
	print(text("-", "d", "").message)
	print(text("-", "d", "own").message)
	print(text("a", "d", "d: seen").message)
	print(text("a", "d", "x").message)
	print(text("a", "d", "").message)
}
// expect-exit: 0
// expect-stdout: d: failed
// expect-stdout: own
// expect-stdout: d: seen
// expect-stdout: d: a: x
// expect-stdout: d: a
