fn lookup(m: Map[Int, Int], k: Int) Int:
	return m[k]

fn build() Int:
	m := {1: 10, 2: 20}
	return lookup(m, 2) + m[1]

fn flags() Int:
	m := {true: 1.5, false: 2.5}
	return 0

fn main() Int:
	return build() + flags()

fn named() Int:
	m := {"one": 1, "two": 2}
	return m["two"]
