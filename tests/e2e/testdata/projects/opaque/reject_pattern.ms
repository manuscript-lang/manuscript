import (
	parse, stringify from "@std/data/json.ms",

	Approved, Mode, approve, safe from "./gate.ms",
)

export fn main() Int:
	{entity} := approve("u")
	return entity.length()
