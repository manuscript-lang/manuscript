import (
	parse, stringify from "@std/data/yaml.ms",
	arguments from "@std/os/env.ms",
)

fn main() Unit:
	for text in arguments():
		result := parse(text)
		print(result)
		if value := result: print(stringify(value))
