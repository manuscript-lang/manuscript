import (
	Approved, Mode, approve, safe from "./gate.ms",
	parse, stringify from "@std/data/json.ms",
)

export fn main() Int:
	s := stringify(approve("u"))
	return 0
