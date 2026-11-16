import (
	environment from "@std/os/env.ms",
	now from "@std/time.ms",
)

// ms: allow_effect std.clock.read
// ms: allow_effect std.env.read
export fn banner() String!:
	env := environment()?
	user := env.get("USER").get("someone")
	return ok(f"hello {user}, it is {now().to_string()}")
