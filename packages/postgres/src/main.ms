import (
	Config, open from "./conn.ms",
	Value from "./value.ms",
)

fn main() Unit!:
	var conn = open(Config(port: 5433, password: "secret"))?
	rows := conn.query(
		"select $1::int8 + 1 as n, $2::text as t, null::int as z",
		[Value.Int(41), Value.Text("hi")],
	)?
	print("{rows.columns} {rows.command}")
	for row in rows.rows:
		for v in row: print("{v}")
	conn.close()?
	return ok(unit)
