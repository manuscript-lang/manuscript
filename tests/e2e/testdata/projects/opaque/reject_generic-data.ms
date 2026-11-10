import (
	Approved, Mode, approve, safe from "./gate.ms",
	parse, stringify from "@std/data/json.ms",
)

fn wrap[T](v: T) String:
	return stringify(v).get("")

export fn main() Int:
	return wrap(approve("u")).length()
