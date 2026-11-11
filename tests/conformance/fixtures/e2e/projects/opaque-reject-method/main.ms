import (
	parse, stringify from "@std/data/json.ms",

	Approved, Mode, approve, safe from "./gate.ms",
)

fn Approved.extra() Int:
	return 1

export fn main() Int:
	return 0
