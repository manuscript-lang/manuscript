import (
	parse from "@std/data/toml.ms",
	StringBuilder from "@std/string.ms",
	keep, measure from "@std/test/bench.ms",
)

fn toml_doc(count: Int) String:
	var sb = StringBuilder()
	for i in 0..count:
		sb.append("[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
	return sb.build()

bench "toml.parse":
	toml := toml_doc(2000)

	fn work() Result[Unit, Error]:
		if parse(toml).is_ok(): return keep(1)
		return keep(0)

	measure(2000, work)?
