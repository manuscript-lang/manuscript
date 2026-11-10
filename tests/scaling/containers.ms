// Runtime half of the scaling gate (`ms run tools/scaling-check.ms`): one pass of container and string work whose
// size is the first argument. Each phase prints `<name> <nanoseconds>`; the gate compares the same phase at two
// sizes, so a phase that should be linear cannot silently become quadratic.
import (
	stdout from "@std/io/io.ms",
	Instant, monotonic from "@std/time.ms",
	arguments from "@std/os/env.ms",
	StringBuilder from "@std/string.ms",
	SortedMap from "@std/collections/sorted.ms",
)

fn say(text: String) Unit:
	_ignored := stdout().write(text)

fn report(name: String, started: Instant) Unit:
	say("{name} {monotonic().difference(started).to_nanoseconds()}\n")

fn next(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn list_append(n: Int) Int:
	t := monotonic()
	var xs = List[Int]()
	for i in 0..n:
		xs.append(i)

	var sum = 0
	for i in 0..n:
		sum += xs[i]
	report("list_append_get", t)
	return sum

fn list_sort(n: Int) Int:
	t := monotonic()
	var xs = List[Int]()
	var x = 1

	for i in 0..n:
		x = next(x)
		xs.append(x)

	xs.sort()
	report("list_sort", t)
	return xs[0]

fn map_int(n: Int) Int:
	t := monotonic()
	var m = Map[Int, Int]()
	for i in 0..n:
		m[i] = i

	var hits = 0
	for i in 0..n:
		if m.contains(i):
			hits += 1
	report("map_int", t)
	return hits

fn map_string(n: Int) Int:
	t := monotonic()
	var m = Map[String, Int]()
	for i in 0..n:
		m["key{i}"] = i

	var hits = 0
	for i in 0..n:
		if m.contains("key{i}"):
			hits += 1
	report("map_string", t)
	return hits

fn set_int(n: Int) Int:
	t := monotonic()
	var s = Set[Int]()
	for i in 0..n:
		s.add(i)
	report("set_int", t)
	return s.length()

fn sorted_map(n: Int) Int:
	t := monotonic()
	var m = SortedMap[Int, Int]()
	var x = 1

	for i in 0..n:
		x = next(x)
		m.add(x, i)

	var hits = 0
	x = 1

	for i in 0..n:
		x = next(x)
		if m.contains(x):
			hits += 1

	report("sorted_map", t)
	return hits

fn string_build(n: Int) Int:
	t := monotonic()
	var s = ""
	for i in 0..n:
		s += "ab"

	var b = StringBuilder()
	for i in 0..n:
		b.append("ab")
	report("string_build", t)
	return s.length() + b.build().length()

fn string_scan(n: Int) Int:
	t := monotonic()
	var s = ""
	for i in 0..n:
		s += "ab "

	var words = 0
	for part in s.split(" "):
		words += part.length()

	var sum = 0
	for i in 0..n:
		sum += s.get(i * 3).length()
	report("string_scan", t)
	return words + sum

fn string_replace(n: Int) Int:
	t := monotonic()
	var s = ""
	for i in 0..n:
		s += "ab "

	out := s.replace_each({"ab": "x", " ": "_"})
	report("string_replace", t)
	return out.length()

export fn main() Int:
	args := arguments()
	var n = 10000
	if args.length() > 0:
		n = args[0].parse_int().get(10000)

	var total = 0
	total += list_append(n)
	total += list_sort(n)
	total += map_int(n)
	total += map_string(n)
	total += set_int(n)
	total += sorted_map(n)
	total += string_build(n)
	total += string_scan(n)
	total += string_replace(n)
	if total < 0: return 1

	return 0
