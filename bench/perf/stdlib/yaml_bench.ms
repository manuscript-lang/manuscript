import YamlValue, parse, stringify from "@std/data/yaml.ms"

fn yaml_doc(count Int) String:
	var sb = ""
	for i in 0..count:
		sb += f"- id: {i}\n  name: user{i}\n  tags: [a, b]\n  ok: true\n"
	return sb

fn yaml_length(value YamlValue) Int:
	if text := stringify(value): return text.length()
	return 0

type BenchData:
	yaml String
	yaml_2 String
	tree YamlValue

fn make_fixture() BenchData:
	yaml := yaml_doc(2000)
	yaml_2 := yaml_doc(2000)
	tree := parse(yaml_doc(2000)).get()
	return BenchData(yaml: yaml, yaml_2: yaml_2, tree: tree.clone())

bench "yaml.parse" per 2000:
	parse(fixture.yaml).is_ok()

bench "yaml.roundtrip" per 2000:
	yaml_length(parse(fixture.yaml_2).get())

bench "yaml.stringify" per 2000:
	yaml_length(fixture.tree)
