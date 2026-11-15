// Query throughput: WORKERS connections each run QUERIES sequential point lookups with
// one prepared statement.
import (
	promise from "@std/concurrency/promise.ms",
	arguments, environment from "@std/os/env.ms",

	Config, open from "@pg/conn.ms",
	Value from "@pg/value.ms",
)

fn config() Config!:
	env := environment()?
	return ok(
		Config(
			host: env.get_or("PGHOST", "127.0.0.1"),
			port: env.get_or("PGPORT", "5432").parse_int().ok_or(
				Error("bad PGPORT")
			)?,
			user: env.get_or("PGUSER", "postgres"),
			password: env.get_or("PGPASSWORD", ""),
		)
	)

fn worker(id: Int, queries: Int) Int!:
	cfg := config()?
	var conn = open(cfg)?
	statement := conn.prepare(
		"lookup",
		"select id, name, score from items where id = $1",
	)?
	var sum = 0

	for i in 0..queries:
		key := (i * 7919 + id * 104729) % 10000 + 1
		rows := conn.run(statement, [Value.Int(key)])?

		match rows.rows[0][2]:
			Value.Int(score): sum += score
			_: return error(Error("score is not an integer"))

	conn.close()?
	return ok(sum)

// Creates the table the lookups read: 10000 rows of (id, name, score).
fn setup(cfg: Config) Void!:
	var conn = open(cfg)?
	void conn.simple("drop table if exists items")?
	void conn.simple(
		"create table items (id int8 primary key, name text not null, score int8 not null)"
	)?
	void conn.simple(
		"insert into items select g, 'item-' || g, (g * 37) % 1000 from generate_series(1, 10000) g"
	)?
	void conn.simple("analyze items")?
	conn.close()?
	return ok(void)

fn main() Void!:
	args := environment()?
	workers := args.get_or("WORKERS", "4").parse_int().ok_or(Error("bad WORKERS"))?
	queries := args.get_or("QUERIES", "20000").parse_int().ok_or(Error("bad QUERIES"))?
	cfg := config()?
	args_list := arguments()
	if args_list.length() > 0 and args_list[0] == "setup": return setup(cfg)

	tasks := (0..workers).map(fn id: promise(fn: worker(id, queries)))
	var total = 0
	for task in tasks: total += task.wait()?
	print("checksum {total}")
	return ok(void)
