import parse from "@std/data/toml.ms"

fn toml_doc(count Int) String {
	var sb = ""
	for i in 0..count {
		sb += f"[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n"
	}
	return sb
}

type BenchData {
	toml String
}

fn make_fixture() BenchData {
	toml := toml_doc(2000)
	return BenchData(toml: toml)
}

bench "toml.parse" per 2000 {
	parse(fixture.toml).is_ok()
}
