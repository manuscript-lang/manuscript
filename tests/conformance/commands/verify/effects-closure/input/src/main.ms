fn make() fn(String) Void:
	return fn(text String) Void:
		print(text)

fn main() Int:
	make()("a")
	return 0
