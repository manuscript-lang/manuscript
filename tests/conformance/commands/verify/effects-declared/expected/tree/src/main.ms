// ms: effect db.write
// ms: allow_effect std.console.write
fn save(text String) Void {
	print(text)
}

fn caller(text String) Void {
	save(text)
}

// ms: allow_effect db.*
fn domain(text String) Void {
	save(text)
}

fn main() Int {
	caller("a")
	domain("b")
	return 0
}
