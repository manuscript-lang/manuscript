import (
	Bytes from "@std/bytes.ms",
	Promise, promise from "@std/concurrency/promise.ms",
	Connection, listen from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	environment from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	expect_equal, expect_error, expect_true from "@std/test/test.ms",

	md5_password from "@pg/auth.ms",
	Config, Conn, open from "@pg/conn.ms",
	Pool, Statement, start from "@pg/pool.ms",
	Value from "@pg/value.ms",
	Backend, DATA_ROW, decode_message from "@pg/wire.ms",
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
	expect_equal(
		md5_password("postgres", "secret", salt),
		"md5bb41a296aab6baccb36ff243a562abff",
	)?

test "a recorded DataRow decodes with a NULL column":
	// two columns: "ab" and NULL
	body := Bytes([0, 2, 0, 0, 0, 2, 97, 98, 255, 255, 255, 255])

	match decode_message(DATA_ROW, body)?:
		Backend.DataRow(columns):
			expect_equal(columns.length(), 2)?
			expect_true(columns[1].is_none())?
		_: expect_true(false)?

test "extended query returns typed values":
	var conn = open(config()?)?
	rows := conn.query(
		"select $1::int8 + 1, $2::text, $3::bool, $4::float8, null::int, $5::bytea",
		[
			Value.Int(41),
			Value.Text("hi"),
			Value.Bool(true),
			Value.Float(1.5),
			Value.Bytes(Bytes([0, 255])),
		],
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

test "a prepared statement runs repeatedly with typed results":
	var conn = open(config()?)?
	statement := conn.prepare("double", "select $1::int * 2 as twice")?

	for n in 0..3:
		rows := conn.run(statement, [Value.Int(n)])?
		expect_equal(rows.rows[0][0], Value.Int(n * 2))?
		expect_equal(rows.columns[0], "twice")?

	conn.close()?

test "transactions commit and roll back":
	var conn = open(config()?)?
	void conn.simple("create temp table t (n int)")?
	conn.begin()?
	void conn.query("insert into t values ($1)", [Value.Int(1)])?
	conn.rollback()?

	none_left := conn.query("select count(*) from t", [])?
	expect_equal(none_left.rows[0][0], Value.Int(0))?
	conn.begin()?
	void conn.query("insert into t values ($1)", [Value.Int(1)])?
	conn.commit()?

	one_left := conn.query("select count(*) from t", [])?
	expect_equal(one_left.rows[0][0], Value.Int(1))?
	conn.close()?

test "a wrong password is rejected":
	cfg := config()?
	failure := expect_error(
		open(
			Config(
				host: cfg.host.clone(),
				port: cfg.port,
				user: cfg.user.clone(),
				password: "wrong",
			)
		)
	)?
	expect_equal(failure.kind, "28P01")?

test "a pool runs statements concurrently and returns results in order":
	var pool = start(config()?, 3)?
	statements := (0..7).map(
		fn n: Statement("select $1::int, pg_sleep(0.05)", [Value.Int(n)])
	)
	results := pool.query_all(statements)?
	expect_equal(results.length(), 7)?
	for n in 0..7: expect_equal(results[n].rows[0][0], Value.Int(n))?

	single := pool.query("select 5::int")?
	expect_equal(single.rows[0][0], Value.Int(5))?
	pool.close()?

test "a pool reports a server error and keeps working":
	var pool = start(config()?, 2)?
	failure := expect_error(pool.query("select 1/0"))?
	expect_equal(failure.kind, "22012")?

	ok_rows := pool.query("select 1")?
	expect_equal(ok_rows.rows[0][0], Value.Int(1))?
	pool.close()?

fn login(user: String, password: String, allow_md5: Bool) Conn!:
	cfg := config()?
	return open(
		Config(
			host: cfg.host.clone(),
			port: cfg.port,
			user: user,
			password: password,
			allow_md5: allow_md5,
		)
	)

test "md5 login is refused unless allowed":
	failure := expect_error(login("md5user", "md5pass", false))?
	expect_equal(failure.kind, "EACCES")?

	var conn = login("md5user", "md5pass", true)?
	rows := conn.query("select current_user", [])?
	expect_equal(rows.rows[0][0], Value.Text("md5user"))?
	conn.close()?

test "a cleartext password is refused without TLS":
	failure := expect_error(login("clearuser", "clearpass", true))?
	expect_equal(failure.kind, "EACCES")?

fn impostor_accept(accepted: Promise[Connection]) Void!:
	var client = accepted.wait()?
	return impostor(var client)

// A server that offers SCRAM and then says "authenticated" without ever proving it
// knows the password.
fn impostor(var client: Connection) Void!:
	void client.input.next()?

	// R, length 23, method 10, "SCRAM-SHA-256", two NULs
	offer := Bytes(
		[
			82, 0, 0, 0, 23, 0, 0, 0, 10, 83, 67, 82, 65, 77, 45, 83, 72, 65, 45, 50,
			53, 54, 0, 0
		]
	)
	client.output.write(offer)?
	void client.input.next()?
	client.output.write(Bytes([82, 0, 0, 0, 8, 0, 0, 0, 0]))?
	client.close()?
	return ok()

test "a server that skips the SCRAM proof is rejected":
	var listener = listen("127.0.0.1:0")?
	accepted := listener.accept()
	port := listener.address().split(":")[1].parse_int().ok_or(Error("bad address"))?
	accepting := promise(fn: impostor_accept(accepted))
	failure := expect_error(open(Config(port: port, password: "secret")))?
	expect_equal(failure.kind, "EACCES")?
	accepting.wait()?
	listener.close()?

test "transaction commits on success and rolls back on error":
	var conn = open(config()?)?
	void conn.simple("create temp table tx (n int)")?

	added := conn.transaction(
		fn(var c: Conn): c.query("insert into tx values (1)", [])
	)?
	expect_equal(added.command, "INSERT 0 1")?
	void expect_error(
		conn.transaction(
			fn(var c: Conn): c.query("insert into tx values (1/0)", [])
		)
	)?

	count := conn.query("select count(*) from tx", [])?
	expect_equal(count.rows[0][0], Value.Int(1))?
	conn.close()?

test "TLS login upgrades the socket after an SSLRequest":
	env := environment()?
	roots := (read_file(env.get_or("PGSSLROOTCERT", "")).wait()?).decode_utf8().ok_or(
		Error("bad certificate")
	)?
	cfg := config()?
	var conn = open(
		Config(
			host: cfg.host.clone(),
			port: cfg.port,
			user: cfg.user.clone(),
			password: cfg.password.clone(),
			tls: TlsOptions(server_name: "localhost", roots_pem: roots),
		)
	)?
	rows := conn.query("select ssl from pg_stat_ssl where pid = pg_backend_pid()", [])?
	expect_equal(rows.rows[0][0], Value.Bool(true))?
	conn.close()?

// A server that answers the SSL request with `N`: no TLS here.
fn refuser(var client: Connection) Void!:
	void client.input.next()?
	client.output.write(Bytes([78]))?
	client.close()?
	return ok()

fn refuser_accept(accepted: Promise[Connection]) Void!:
	var client = accepted.wait()?
	return refuser(var client)

test "a server that refuses TLS is an error and not a plaintext fallback":
	var listener = listen("127.0.0.1:0")?
	accepted := listener.accept()
	port := listener.address().split(":")[1].parse_int().ok_or(Error("bad address"))?
	accepting := promise(fn: refuser_accept(accepted))
	failure := expect_error(
		open(Config(port: port, tls: TlsOptions(server_name: "localhost")))
	)?
	expect_equal(failure.kind, "ENOTSUP")?
	accepting.wait()?
	listener.close()?
