import (
	YamlValue, parse, stringify from "@std/data/yaml.ms",
	StringBuilder from "@std/string_builder.ms",
	keep, measure from "@std/test/bench.ms",
)

fn yaml_doc(count: Int) String:
	var sb = StringBuilder()
	for i in 0..count:
		sb.append("- id: {i}\n  name: user{i}\n  tags: [a, b]\n  ok: true\n")
	return sb.build()

fn yaml_length(value: YamlValue) Int:
	if text := stringify(value): return text.length()
	return 0

bench "yaml.parse":
	yaml := yaml_doc(2000)

	fn work() Result[Unit, Error]:
		if parse(yaml).is_ok(): return keep(1)
		return keep(0)

	measure(2000, work)?

bench "yaml.roundtrip":
	yaml := yaml_doc(2000)

	fn work() Result[Unit, Error]:
		if v := parse(yaml): return keep(yaml_length(v))
		return keep(0)

	measure(2000, work)?

bench "yaml.stringify":
	yaml := yaml_doc(2000)
	if v := parse(yaml):
		measure(2000, fn: keep(yaml_length(v)))?
