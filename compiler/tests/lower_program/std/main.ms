import minutes, seconds from "@std/time.ms"

fn shout(n: Int) Int:
	return n * 2

fn main() Int:
	xs := [1, 2, 3]
	a := seconds(shout(xs.length()))
	b := minutes(1)
	if a == b: return 1

	return 0
