import (
	environment from "@std/os/env.ms",

	Config, open from "@postgres/conn.ms",
	Value from "@postgres/value.ms",
)

// Runs one query through the package, fetched as a git dependency.
fn main() Unit!:
	env := environment()?
	port := env.get_or("PGPORT", "5432").parse_int().ok_or(Error("bad PGPORT"))?
	var conn = open(Config(port: port, password: env.get_or("PGPASSWORD", "")))?
	rows := conn.query("select $1::int8 + 1", [Value.Int(41)])?
	print("{rows.rows[0][0]}")
	conn.close()?
	return ok(unit)
