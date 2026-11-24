import (
	HttpRequest, HttpResponse, buffered, text from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	environment from "@std/os/env.ms",

	Config, open from "@pg/conn.ms",
	Value from "@pg/value.ms",
)

// Connection settings come from PGHOST, PGPORT, PGUSER, PGPASSWORD and PGDATABASE.
fn config() Config!:
	env := environment()?
	return ok(
		Config(
			host: env.get_or("PGHOST", "127.0.0.1"),
			port: env.get_or("PGPORT", "5432").parse_int().get(5432),
			user: env.get_or("PGUSER", "postgres"),
			password: env.get_or("PGPASSWORD", ""),
			database: env.get_or("PGDATABASE", "postgres"),
		)
	)

// Records one visit to `path` and returns how many visits the table holds.
fn record_visit(path String) Int!:
	var conn = open(config()?)?
	void conn.simple("create table if not exists visits (path text not null)")?
	void conn.query("insert into visits (path) values ($1)", [Value.Text(path)])?

	rows := conn.query("select count(*) from visits", [])?
	conn.close()?

	count := rows.rows[0][0]

	match count:
		Value.Int(total) => return ok(total)
		_ => return error(Error("count(*) was not an integer", kind: "EBADMSG"))

fn visit(request HttpRequest) HttpResponse:
	result := record_visit(request.path)
	if result.is_error(): return text(500, "the database did not answer\n")

	return text(200, f"visit {result.get()}\n")

fn main() Void!:
	server := serve("127.0.0.1:8080", buffered(visit))?
	print(f"listening on http://{server.address()}/")
	server.wait()?
