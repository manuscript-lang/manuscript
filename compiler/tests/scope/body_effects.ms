// ms: allow_effect std.fs.*

// ms: effect db.write
fn save(n: Int) Int:
	return n

// ms: allow_effect db.*
fn store(n: Int) Int:
	return save(n) + 1

fn pure(n: Int) Int:
	return n + 1

fn main() Int:
	return store(pure(2))
