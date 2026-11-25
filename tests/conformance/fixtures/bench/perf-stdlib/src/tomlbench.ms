import (
	parse from "@std/data/toml.ms",

	bench from "./harness.ms",
)

fn toml_doc(count Int) String {
	var sb = ""
	for i in 0..count {
		sb += f"[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n"
	}
	return sb
}

export fn bench_toml() Void {
	toml := toml_doc(2000)

	bench(
		"toml.parse",
		2000,
		fn() Int {
			if parse(toml).is_ok() {
				return 1
			} return 0
		}
	)
}
