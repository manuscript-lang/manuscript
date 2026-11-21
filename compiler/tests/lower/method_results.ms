import stdout from "@std/io/io.ms"

fn say(text: String) Void:
	written := stdout().write(f"{text}\n")

fn main() Int:
	say("x")
	return 0
