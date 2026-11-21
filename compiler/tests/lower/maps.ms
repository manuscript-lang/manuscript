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

fn size(m: Map[Int, Int]) Int:
	return m.length()

fn has(m: Map[Int, Int], k: Int) Bool:
	return m.contains(k)

fn has_name(m: Map[String, Float], key: String) Bool:
	return m.contains(key)

fn has_flag(m: Map[Bool, Int], f: Bool) Bool:
	return m.contains(f)

fn main() Int:
	counts := {1: 10, 2: 20}
	rates := {"a": 0.5}
	marks := {true: 1}
	if has(counts, 1) and has_name(rates, "a") and has_flag(marks, false):
		return size(counts)
	a := build() + pick(2) + named("two")
	b := flags(true) + prices("a")
	if tagged(1) and b > 1.0: return a

	return 0
