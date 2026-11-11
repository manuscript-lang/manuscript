import (
	parse, stringify from "@std/data/json.ms",

	Approved, Mode, approve, safe from "./gate.ms",
)

fn Approved.extra() Int:
	return 1

fn main() Unit:
	return
