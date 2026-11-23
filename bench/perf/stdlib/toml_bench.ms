import (
	parse from "@std/data/toml.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn toml_doc(count: Int) String:
	var sb = StringBuilder()
	for i in 0..count:
		sb.append(f"[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
	return sb.build()

type BenchData:
	toml: String

fn make_fixture() BenchData:
	toml := toml_doc(2000)
	return BenchData(toml: toml)

bench "toml.parse" per 2000:
	parse(fixture.toml).is_ok()
