import (
	Config from "./conn.ms",
	start from "./pool.ms",
)

fn main() Unit!:
	var pool = start(Config(port: 5433, password: "secret"), 2)?
	rows := pool.query("select 5::int")?
	print("{rows.rows[0][0]}")
	return pool.close()
