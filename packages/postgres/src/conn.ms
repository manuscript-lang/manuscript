// One PostgreSQL connection: startup, authentication, queries and transactions.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Connection, connect from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	Duration from "@std/time.ms",

	md5_password, scram_start from "@pg/auth.ms",
	Value, decode_value, encode_value from "@pg/value.ms",
	Backend,
	Field,
	PORTAL,
	STATEMENT,
	STATUS_IDLE,
	bind,
	decode_message,
	describe,
	execute,
	i32,
	parse,
	password,
	query,
	sasl_initial,
	sasl_response,
	startup,
	sync,
	terminate from "@pg/wire.ms",
)

// How to reach the server and which logins to accept.
export type Config:
	host: String = "127.0.0.1"
	port: Int = 5432
	user: String = "postgres"
	password: String = ""
	database: String = "postgres"
	application_name: String = "manuscript"
	// TLS from the first byte (PostgreSQL 17 direct negotiation, ALPN `postgresql` is
	// added); none is plain TCP.
	tls: TlsOptions? = none
	// Accept an md5 password challenge. Off by default: md5 is weak, and SCRAM-SHA-256
	// is always accepted.
	allow_md5: Bool = false
	timeout: Duration? = none

// The result of one statement.
export type Rows:
	columns: List[String]
	rows: List[List[Value]]
	// The command tag, such as `SELECT 3` or `INSERT 0 1`.
	command: String

// Rows changed, from a command tag such as `UPDATE 2`; none when the tag carries no
// count.
fn Rows.affected() Int?:
	parts := self.command.split(" ")
	return parts[parts.length() - 1].parse_int()

// An open connection. One owner at a time; use a `Pool` to share.
export type Conn:
	net: Connection
	buffer: Bytes
	pos: Int
	parameters: Map[String, String]
	pid: Int
	secret: Int
	// The transaction status of the last ReadyForQuery: `STATUS_IDLE`,
	// `STATUS_IN_TRANSACTION` or `STATUS_FAILED`.
	status: UInt8

fn server_error(fields: Map[String, String]) Error:
	var details = Map[String, String]()
	for entry in fields: details.add(entry.key.clone(), entry.value.clone())
	return Error(
		fields.get_or("M", "server error"),
		kind: fields.get_or("C", "XX000"),
		details: details,
	)

fn protocol(what: String) Error:
	return Error("postgres: {what}", kind: "EPROTO")

// Makes at least `count` unread bytes available, joining chunks once so a large message
// costs linear time.
fn var Conn.need(count: Int) Unit!:
	if self.buffer.length() - self.pos >= count: return ok(unit)

	var joined = BytesBuilder()
	joined.append_bytes(self.buffer.slice(self.pos, self.buffer.length())?)

	var total = self.buffer.length() - self.pos

	while total < count:
		chunk := self.net.input.next()?
		if chunk.is_none(): return error(
			Error(
				"postgres: connection closed by server",
				kind: "ECONNRESET",
			)
		)

		piece := chunk.get(Bytes([]))
		total += piece.length()
		joined.append_bytes(piece)

	self.buffer = joined.build()
	self.pos = 0
	return ok(unit)

// Reads the next message, skipping notices, parameter changes and ignorable messages. A
// server error arrives as `ErrorResponse`, since the server keeps the stream in step
// after it.
fn var Conn.read() Backend!:
	while true:
		self.need(5)?

		code := self.buffer.uint8(self.pos)?
		size := i32(self.buffer, self.pos + 1)?
		if size < 4: return error(protocol("invalid message length"))

		self.need(size + 1)?

		body := self.buffer.slice(self.pos + 5, self.pos + 1 + size)?
		self.pos += 1 + size

		message := decode_message(code, body)?

		match message:
			Backend.NoticeResponse(_): continue
			Backend.Ignored: continue
			Backend.ParameterStatus(name, value):
				self.parameters.add(name.clone(), value.clone())
				continue
			_: return ok(message)

	return error(protocol("unreachable"))

fn var Conn.send(data: Bytes) Unit!:
	self.net.output.write(data)?

fn tls_with_alpn(tls: TlsOptions?) TlsOptions?:
	if options := tls:
		var copy = options.clone()
		copy.alpn = ["postgresql"]
		return copy

	return none

// Connects, authenticates, and returns a connection ready for queries.
export fn open(config: Config) Conn!:
	address := "{config.host}:{config.port}"
	net := connect(address, tls_with_alpn(config.tls), config.timeout.clone()).wait()?
	var conn = Conn(net, Bytes([]), 0, Map[String, String](), 0, 0, STATUS_IDLE)
	var options = Map[String, String]()
	options.add("application_name", config.application_name.clone())
	conn.send(startup(config.user, config.database, options)?)?
	conn.authenticate(config)?
	return ok(conn)

fn var Conn.authenticate(config: Config) Unit!:
	var scram = scram_start(config.password.clone())?
	var in_scram = false
	var server_verified = false

	while true:
		message := self.read()?

		match message:
			Backend.AuthOk:
				if in_scram and not server_verified:
					return error(
						Error(
							"postgres: server did not prove it knows the password",
							kind: "EACCES",
						)
					)

				break
			Backend.AuthCleartext:
				if config.tls.is_none():
					return error(
						Error(
							"postgres: refusing a cleartext password without TLS",
							kind: "EACCES",
						)
					)
				self.send(password(config.password)?)?
			Backend.AuthMd5(salt):
				if not config.allow_md5:
					return error(
						Error(
							"postgres: server asked for md5; set allow_md5 to accept it",
							kind: "EACCES",
						)
					)
				self.send(password(md5_password(config.user, config.password, salt))?)?
			Backend.AuthSasl(mechanisms):
				if not mechanisms.contains("SCRAM-SHA-256"):
					return error(protocol("server offers no SCRAM-SHA-256"))

				in_scram = true
				self.send(sasl_initial("SCRAM-SHA-256", scram.first_message())?)?
			Backend.AuthSaslContinue(data):
				text := data.decode_utf8().ok_or(
					protocol("SCRAM message is not UTF-8")
				)?
				self.send(sasl_response(scram.respond(text)?)?)?
			Backend.AuthSaslFinal(data):
				text := data.decode_utf8().ok_or(
					protocol("SCRAM message is not UTF-8")
				)?
				scram.verify(text)?
				server_verified = true
			Backend.ErrorResponse(fields): return error(server_error(fields))
			_: return error(protocol("unexpected message during login"))

	while true:
		message := self.read()?

		match message:
			Backend.BackendKeyData(pid, secret):
				self.pid = pid
				self.secret = secret
			Backend.ReadyForQuery(status):
				self.status = status
				return ok(unit)
			Backend.ErrorResponse(fields): return error(server_error(fields))
			_: continue

	return ok(unit)

// Reads messages up to ReadyForQuery, collecting rows. A server error or a value that
// cannot be decoded is remembered, and the first one is returned once the server has
// finished, so the connection stays usable. A failed read ends the connection and
// returns at once.
fn var Conn.collect(known: List[Field]) Rows!:
	var fields = known.clone()
	var rows = List[List[Value]]()
	var command = ""
	var failure: Error? = none

	while true:
		message := self.read()?

		match message:
			Backend.RowDescription(found): fields = found.clone()
			Backend.DataRow(columns):
				var row = List[Value]()

				for i in 0..columns.length():
					if i >= fields.length():
						if failure.is_none(): failure = protocol(
							"row has more columns than its description"
						)
						break

					decoded := decode_value(fields[i].type_oid, columns[i].clone())

					if decoded.is_error():
						if failure.is_none(): failure = decoded.err().clone()
						break

					row.append(decoded?)
				rows.append(row)
			Backend.CommandComplete(tag): command = tag.clone()
			Backend.ErrorResponse(found):
				if failure.is_none(): failure = server_error(found)
			Backend.ReadyForQuery(status):
				self.status = status
				break
			_: continue

	if f := failure: return error(f)

	return ok(Rows(fields.map(fn f: f.name.clone()), rows, command))

// Runs a statement with no parameters over the simple protocol; may hold several
// statements.
fn var Conn.simple(sql: String) Rows!:
	self.send(query(sql)?)?
	return self.collect([])

// Runs one statement with parameters in a single round trip.
fn var Conn.query(sql: String, params: List[Value]) Rows!:
	var out = BytesBuilder()
	out.append_bytes(parse("", sql, [])?)
	out.append_bytes(bind("", "", params.map(fn p: encode_value(p)), false)?)
	out.append_bytes(describe(PORTAL, "")?)
	out.append_bytes(execute("", 0)?)
	out.append_bytes(sync()?)
	self.send(out.build())?
	return self.collect([])

fn var Conn.begin() Unit!:
	_ := self.simple("BEGIN")?
	return ok(unit)

fn var Conn.commit() Unit!:
	_ := self.simple("COMMIT")?
	return ok(unit)

fn var Conn.rollback() Unit!:
	_ := self.simple("ROLLBACK")?
	return ok(unit)

fn var Conn.close() Unit!:
	_ := self.send(terminate()?)
	return self.net.close()

// A statement parsed once on the server and run many times.
export type Prepared:
	name: String
	columns: List[Field]

// Parses `sql` under `name` and learns its result columns.
fn var Conn.prepare(name: String, sql: String) Prepared!:
	var out = BytesBuilder()
	out.append_bytes(parse(name, sql, [])?)
	out.append_bytes(describe(STATEMENT, name)?)
	out.append_bytes(sync()?)
	self.send(out.build())?

	var columns = List[Field]()
	var failure: Error? = none

	while true:
		message := self.read()?

		match message:
			Backend.RowDescription(found): columns = found.clone()
			Backend.ErrorResponse(found):
				if failure.is_none(): failure = server_error(found)
			Backend.ReadyForQuery(status):
				self.status = status
				break
			_: continue

	if f := failure: return error(f)

	return ok(Prepared(name.clone(), columns))

// Runs a prepared statement: bind, execute and sync in one round trip.
fn var Conn.run(statement: Prepared, params: List[Value]) Rows!:
	var out = BytesBuilder()
	out.append_bytes(
		bind("", statement.name, params.map(fn p: encode_value(p)), false)?
	)
	out.append_bytes(execute("", 0)?)
	out.append_bytes(sync()?)
	self.send(out.build())?
	return self.collect(statement.columns)

// Runs `body` in a transaction: commits when it returns a value, rolls back when it
// returns an error (the body's error is returned, whatever the rollback reports).
fn var Conn.transaction[T](body: fn(var Conn) T!) T!:
	self.begin()?

	result := body(var self)

	if result.is_error():
		_ := self.rollback()
		return result

	self.commit()?
	return result
