import (
	now, seconds from "@std/time.ms",

	load_name from "./store.ms",
)

// ms: allow_effect std.clock.read
// ms: allow_effect std.fs.read
export fn banner() String!:
	name := load_name()?
	later := now().shift(seconds(0))?
	return ok(f"hello {name}, it is {later.to_string()}")
