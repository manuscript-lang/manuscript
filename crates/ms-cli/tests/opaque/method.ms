import approve, Approved, Mode, safe from "./gate.ms"
import parse, stringify from "@std/data/json.ms"

fn Approved.extra() Int:
	return 1

fn main() Unit:
	return
