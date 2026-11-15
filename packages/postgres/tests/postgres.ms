import (
	Bytes from "@std/bytes.ms",
	environment from "@std/os/env.ms",
	expect_equal, expect_error, expect_true from "@std/test/test.ms",

	Config, Conn, open from "../src/conn.ms",
	md5_password from "../src/auth.ms",
	Backend, decode_message from "../src/wire.ms",
	Value from "../src/value.ms",
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

test "md5 password response matches the server algorithm":
	salt := Bytes([1, 2, 3, 4])
	expect_equal(md5_password("postgres", "secret", salt), "md5bb41a296aab6baccb36ff243a562abff")?

test "a recorded DataRow decodes with a NULL column":
	// two columns: "ab" and NULL
	body := Bytes([0, 2, 0, 0, 0, 2, 97, 98, 255, 255, 255, 255])
	match decode_message(68, body)?:
		Backend.DataRow(columns):
			expect_equal(columns.length(), 2)?
			expect_true(columns[1].is_none())?
		_: expect_true(false)?

test "extended query returns typed values":
	var conn = open(config()?)?
	rows := conn.query(
		"select $1::int8 + 1, $2::text, $3::bool, $4::float8, null::int, $5::bytea",
		[Value.Int(41), Value.Text("hi"), Value.Bool(true), Value.Float(1.5), Value.Bytes(Bytes([0, 255]))],
	)?
	expect_equal(rows.rows[0][0], Value.Int(42))?
	expect_equal(rows.rows[0][1], Value.Text("hi"))?
	expect_equal(rows.rows[0][2], Value.Bool(true))?
	expect_equal(rows.rows[0][3], Value.Float(1.5))?
	expect_equal(rows.rows[0][4], Value.Null)?
	expect_equal(rows.rows[0][5], Value.Bytes(Bytes([0, 255])))?
	expect_equal(rows.command, "SELECT 1")?
	conn.close()?

test "a server error carries its SQLSTATE and leaves the connection usable":
	var conn = open(config()?)?
	failure := expect_error(conn.query("select 1/0", []))?
	expect_equal(failure.kind, "22012")?
	rows := conn.query("select 7", [])?
	expect_equal(rows.rows[0][0], Value.Int(7))?
	conn.close()?

test "transactions commit and roll back":
	var conn = open(config()?)?
	_ := conn.simple("create temp table t (n int)")?
	conn.begin()?
	_ := conn.query("insert into t values ($1)", [Value.Int(1)])?
	conn.rollback()?
	none_left := conn.query("select count(*) from t", [])?
	expect_equal(none_left.rows[0][0], Value.Int(0))?
	conn.begin()?
	_ := conn.query("insert into t values ($1)", [Value.Int(1)])?
	conn.commit()?
	one_left := conn.query("select count(*) from t", [])?
	expect_equal(one_left.rows[0][0], Value.Int(1))?
	conn.close()?

test "a wrong password is rejected":
	cfg := config()?
	failure := expect_error(open(Config(host: cfg.host.clone(), port: cfg.port, user: cfg.user.clone(), password: "wrong")))?
	expect_equal(failure.kind, "28P01")?
