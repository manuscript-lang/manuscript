// One PostgreSQL connection: startup, authentication, queries and transactions.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Connection, connect from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	Duration from "@std/time.ms",

	md5_password, scram_start from "./auth.ms",
	Value, decode_value, encode_value from "./value.ms",
	Backend,
	Field,
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
	terminate from "./wire.ms",
)

// How to reach the server.
export type Config:
	host: String = "127.0.0.1"
	port: Int = 5432
	user: String = "postgres"
	password: String = ""
	database: String = "postgres"
	application_name: String = "manuscript"
	// TLS from the first byte (PostgreSQL 17 direct negotiation); none is plain TCP.
	tls: TlsOptions? = none
	timeout: Duration? = none

// The result of one statement.
export type Rows:
	columns: List[String]
	rows: List[List[Value]]
	// The command tag, such as `SELECT 3` or `INSERT 0 1`.
	command: String

// Rows changed, from a command tag such as `UPDATE 2`; zero when the tag has no count.
fn Rows.affected() Int:
	parts := self.command.split(" ")
	return parts[parts.length() - 1].parse_int().get(0)

// An open connection. One owner at a time; use a `Pool` to share.
export type Conn:
	net: Connection
	buffer: Bytes
	pos: Int
	parameters: Map[String, String]
	pid: Int
	secret: Int
	// 73 idle, 84 in a transaction, 69 in a failed transaction.
	status: Int

fn server_error(fields: Map[String, String]) Error:
	var details = Map[String, String]()
	for entry in fields: details.add(entry.key.clone(), entry.value.clone())
	return Error(
		fields.get_or("M", "server error"),
		kind: fields.get_or("C", "XX000"),
		details: details,
	)

fn var Conn.fill() Unit!:
	chunk := self.net.input.next()?
	if chunk.is_none(): return error(
		Error("postgres: connection closed by server", kind: "ECONNRESET")
	)

	rest := self.buffer.slice(self.pos, self.buffer.length())?
	self.buffer = rest.concat(chunk.get(Bytes([])))
	self.pos = 0

// Reads the next message, skipping notices and parameter changes.
fn var Conn.read() Backend!:
	while true:
		while self.buffer.length() - self.pos < 5: self.fill()?

		code := self.buffer.get(self.pos).to_int()
		size := i32(self.buffer, self.pos + 1)?
		while self.buffer.length() - self.pos < size + 1: self.fill()?

		body := self.buffer.slice(self.pos + 5, self.pos + 1 + size)?
		self.pos += 1 + size

		message := decode_message(code, body)?

		match message:
			Backend.NoticeResponse(_): continue
			Backend.ParameterStatus(name, value):
				self.parameters.add(name.clone(), value.clone())
				continue
			Backend.ErrorResponse(fields): return error(server_error(fields))
			_: return ok(message)

	return error(Error("postgres: unreachable", kind: "EIO"))

fn var Conn.send(data: Bytes) Unit!:
	self.net.output.write(data)?

// Connects, authenticates, and returns a connection ready for queries.
export fn open(config: Config) Conn!:
	address := "{config.host}:{config.port}"
	net := connect(address, config.tls.clone(), config.timeout.clone()).wait()?
	var conn = Conn(net, Bytes([]), 0, Map[String, String](), 0, 0, 0)
	var options = Map[String, String]()
	options.add("application_name", config.application_name.clone())
	conn.send(startup(config.user, config.database, options))?
	conn.authenticate(config)?
	return ok(conn)

fn var Conn.authenticate(config: Config) Unit!:
	var scram = scram_start(config.password.clone())?

	while true:
		message := self.read()?

		match message:
			Backend.AuthOk: break
			Backend.AuthCleartext: self.send(password(config.password))?
			Backend.AuthMd5(salt): self.send(
				password(
					md5_password(config.user, config.password, salt)
				)
			)?
			Backend.AuthSasl(_): self.send(
				sasl_initial("SCRAM-SHA-256", scram.first_message())
			)?
			Backend.AuthSaslContinue(data):
				reply := scram.respond(data.decode_utf8().get(""))?
				self.send(sasl_response(reply))?
			Backend.AuthSaslFinal(data): scram.verify(data.decode_utf8().get(""))?
			_: return error(
				Error(
					"postgres: unexpected message during startup",
					kind: "EPROTO",
				)
			)

	while true:
		message := self.read()?

		match message:
			Backend.BackendKeyData(pid, secret):
				self.pid = pid
				self.secret = secret
			Backend.ReadyForQuery(status):
				self.status = status
				return ok(unit)
			_: continue

	return ok(unit)

// Reads messages up to ReadyForQuery, collecting rows. The first error is returned
// after the server has finished, so the connection stays usable.
fn var Conn.collect() Rows!:
	var fields = List[Field]()
	var rows = List[List[Value]]()
	var command = ""
	var failure: Error? = none

	while true:
		message := self.read()

		if message.is_error():
			failure = message.err().clone()

			// An error ends the statement; the server still sends ReadyForQuery.
			continue

		match message?:
			Backend.RowDescription(found): fields = found.clone()
			Backend.DataRow(columns):
				var row = List[Value]()
				for i in 0..columns.length():
					row.append(decode_value(fields[i].type_oid, columns[i].clone())?)
				rows.append(row)
			Backend.CommandComplete(tag): command = tag.clone()
			Backend.ReadyForQuery(status):
				self.status = status
				break
			_: continue

	if f := failure: return error(f)

	return ok(Rows(fields.map(fn f: f.name.clone()), rows, command))

// Runs a statement with no parameters over the simple protocol; may hold several
// statements.
fn var Conn.simple(sql: String) Rows!:
	self.send(query(sql))?
	return self.collect()

// Runs one statement with parameters in a single round trip.
fn var Conn.query(sql: String, params: List[Value]) Rows!:
	var out = BytesBuilder()
	out.append_bytes(parse("", sql, []))
	out.append_bytes(bind("", "", params.map(fn p: encode_value(p)), false))
	out.append_bytes(describe(80, ""))
	out.append_bytes(execute("", 0))
	out.append_bytes(sync())
	self.send(out.build())?
	return self.collect()

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
	_ := self.send(terminate())
	return self.net.close()
