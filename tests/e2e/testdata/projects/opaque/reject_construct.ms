import (
	parse, stringify from "@std/data/json.ms",

	Approved, Mode, approve, safe from "./gate.ms",
)

export fn main() Int:
	a := Approved(entity: "u2", nonce: "x")
	return 0
