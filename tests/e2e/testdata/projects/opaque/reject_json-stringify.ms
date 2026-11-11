import (
	parse, stringify from "@std/data/json.ms",

	Approved, Mode, approve, safe from "./gate.ms",
)

export fn main() Int:
	s := stringify(approve("u"))
	return 0
