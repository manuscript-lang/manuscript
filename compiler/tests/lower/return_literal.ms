fn lit() String:
	return "hello"

fn word(n: Int) String:
	return "w"

export fn main() Int:
	return lit().length() + word(1).length()
