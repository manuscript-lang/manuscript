import stdout from "@std/io/io.ms"

fn f() Void:
	out := stdout()
	void out

fn main() Int:
	f()
	return 0
