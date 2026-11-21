fn lookup(m: Map[Int, Int], k: Int) Int:
	return m[k]

fn build() Int:
	m := {1: 10, 2: 20}
	return lookup(m, 2) + m[1]

fn flags(f: Bool) Float:
	m := {true: 1.5, false: 2.5}
	return m[f]

fn named(key: String) Int:
	m := {"one": 1, "two": 2}
	return m[key]

fn pick(k: Int) Int:
	m := {1: 10, 2: 20, 3: 30}
	return m[k]

fn tagged(k: Int) Bool:
	m := {1: true, 2: false}
	return m[k]

fn prices(key: String) Float:
	m := {"a": 1.5, "b": 2.5}
	return m[key]

fn main() Int:
	a := build() + pick(2) + named("two")
	b := flags(true) + prices("a")
	if tagged(1) and b > 1.0:
		return a
	return 0
