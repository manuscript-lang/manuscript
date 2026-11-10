import lines, stdin from "@std/io/io.ms"

export fn main() Int:
	reader := lines(stdin())
	for line in reader:
		if line == "": return 1
	return 0
