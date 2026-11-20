type Options:
	size: Int
	verbose: Bool = false

fn make(size: Int) Options:
	return Options(size)

fn wrap(size: Int) Options!:
	return ok(Options(size, true))

fn main() Int:
	return make(1).size + wrap(2).get_or(Options(0)).size
