import (
	Approved, Mode, approve, safe from "./gate.ms",
	parse, stringify from "@std/data/json.ms",
)

export fn main() Int:
	var a = approve("u")
	a.nonce = "z"
	return 0
