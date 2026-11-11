import (
	parse, stringify from "@std/data/json.ms",

	Approved, Mode, approve, safe from "./gate.ms",
)

fn wrap[T](v: T) String:
	return stringify(v).get("")

export fn main() Int:
	return wrap(approve("u")).length()
